require './lib/slack_api_helpers'
require './lib/db'

# API module that aims to mimic Slack's API endpoint
module SlackApi
  extend self

  private

  INTERNAL_ERROR = { status: 500, body: { ok: false, error: 'internal_error' } }

  # Common validation for API requests
  def validate_params(params, required_fields = [])
    # Validate required channel
    unless params[:channel] && SlackApiHelpers.validate_channel_id(params[:channel])
      return { status: 400, body: { ok: false, error: 'channel_not_found' } }
    end

    # Validate required fields
    required_fields.each do |field|
      case field
      when :ts
        unless params[:ts] && SlackApiHelpers.validate_timestamp(params[:ts])
          return { status: 400, body: { ok: false, error: 'thread_not_found' } }
        end
      end
    end

    # Validate optional timestamp parameters
    if params[:oldest] && !SlackApiHelpers.validate_timestamp(params[:oldest])
      return { status: 400, body: { ok: false, error: 'invalid_ts_oldest' } }
    end

    if params[:latest] && !SlackApiHelpers.validate_timestamp(params[:latest])
      return { status: 400, body: { ok: false, error: 'invalid_ts_latest' } }
    end

    # Validate cursor
    if params[:cursor]
      direction, ts = SlackApiHelpers.decode_cursor(params[:cursor])
      if direction.nil? || ts.nil?
        return { status: 400, body: { ok: false, error: 'invalid_cursor' } }
      end
    end

    nil # No validation errors
  end

  # Build common query conditions
  def build_base_conditions(channel)
    [
      { '$or' => [{ hidden: { '$ne' => true } }, { subtype: 'tombstone' }] },
      { channel: channel }
    ]
  end

  # Add timestamp filters to conditions
  def build_timestamp_filters(oldest, latest, inclusive)
    conditions = []

    if oldest && SlackApiHelpers.validate_timestamp(oldest)
      operator = inclusive ? '$gte' : '$gt'
      conditions << { ts: { operator => oldest } }
    end

    if latest && SlackApiHelpers.validate_timestamp(latest)
      operator = inclusive ? '$lte' : '$lt'
      conditions << { ts: { operator => latest } }
    end

    conditions
  end

  # Add cursor-based pagination to conditions
  def build_cursor_filters(cursor)
    conditions = []
    cursor_direction, cursor_ts = SlackApiHelpers.decode_cursor(cursor)
    
    if cursor_ts && SlackApiHelpers.validate_timestamp(cursor_ts)
      if cursor_direction == 'before'
        conditions << { ts: { '$lt' => cursor_ts } }
      elsif cursor_direction == 'after'
        conditions << { ts: { '$gt' => cursor_ts } }
      end
    end

    conditions
  end

  # Execute query with pagination
  def execute_paginated_query(conditions, limit, sort_order, cursor_direction)
    all_messages = Messages
      .find({ '$and' => conditions })
      .sort(ts: sort_order)
      .limit(limit + 1)
      .to_a

    has_more = all_messages.length > limit
    return_messages = all_messages.first(limit)

    # Generate next cursor
    next_cursor = nil
    if has_more && !return_messages.empty?
      last_ts = return_messages.last['ts']
      next_cursor = SlackApiHelpers.encode_cursor(last_ts, cursor_direction)
    end

    # Transform messages to Slack format
    slack_messages = return_messages.map do |msg|
      SlackApiHelpers.transform_message_to_slack_format(msg)
    end

    [slack_messages, has_more, next_cursor, nil]
  end

  # Build API response
  def build_response(messages, has_more, next_cursor, additional_fields = {})
    response = {
      ok: true,
      messages: messages,
      has_more: has_more
    }.merge(additional_fields)

    if next_cursor
      response[:response_metadata] = { next_cursor: next_cursor }
    end

    { status: 200, body: response }
  end

  public

  def conversations_history_query(params)
    limit = [params[:limit].to_i, 1000].min
    limit = 100 if limit <= 0

    channel = params[:channel]
    oldest = params[:oldest]
    latest = params[:latest]
    inclusive = params[:inclusive] == 'true' || params[:inclusive] == '1'
    cursor = params[:cursor]

    execute_paginated_query([
      *build_base_conditions(channel),
      # Exclude thread-only messages
      {
        '$or' => [
          { thread_ts: { '$exists' => false } },  # No thread_ts field
          { thread_ts: nil },                     # thread_ts is null
          { '$expr' => { '$eq' => ['$thread_ts', '$ts'] } },  # thread_ts equals ts (thread parent)
          { subtype: 'thread_broadcast' }         # thread_broadcast messages should be shown
        ]
      },
      *build_timestamp_filters(oldest, latest, inclusive),
      *build_cursor_filters(cursor),
    ], limit, -1, 'before')
  end

  def conversations_history_response(params)
    validation_error = validate_params(params)
    return validation_error if validation_error

    begin
      messages, has_more, next_cursor, error = conversations_history_query({
        channel: params[:channel],
        oldest: params[:oldest],
        latest: params[:latest],
        inclusive: params[:inclusive],
        cursor: params[:cursor],
        limit: params[:limit] || 100
      })

      if error
        return { status: 400, body: { ok: false, error: error } }
      end

      additional_fields = { pin_count: 0 }
      additional_fields[:latest] = params[:latest] if params[:latest]

      build_response(messages, has_more, next_cursor, additional_fields)
    rescue => e
      INTERNAL_ERROR
    end
  end

  def conversations_replies_query(params)
    limit = [params[:limit].to_i, 1000].min
    limit = 100 if limit <= 0

    channel = params[:channel]
    ts = params[:ts]
    oldest = params[:oldest]
    latest = params[:latest]
    inclusive = params[:inclusive] == 'true' || params[:inclusive] == '1'
    cursor = params[:cursor]

    # Find the message corresponding to the provided ts
    target_message = Messages.find({ channel: channel, ts: ts }).first
    unless target_message
      return nil, false, nil, 'thread_not_found'
    end

    # If the message has thread_ts and it's different from ts,
    # return only this single message (it's a thread reply)
    if target_message['thread_ts'] && target_message['thread_ts'] != ts
      return [target_message], false, nil, nil
    end

    # Otherwise, return all messages in the thread (ts is the thread parent)
    thread_ts = target_message['ts']

    execute_paginated_query([
      *build_base_conditions(channel),
      # Get all messages in the thread (including the parent)
      {
        '$or' => [
          { ts: thread_ts },  # The parent message
          { thread_ts: thread_ts }  # All replies in the thread
        ],
      },
      *build_timestamp_filters(oldest, latest, inclusive),
      *build_cursor_filters(cursor)
    ], limit, 1, 'after')
  end

  def conversations_replies_response(params)
    validation_error = validate_params(params, [:ts])
    return validation_error if validation_error

    begin
      messages, has_more, next_cursor, error = conversations_replies_query({
        channel: params[:channel],
        ts: params[:ts],
        oldest: params[:oldest],
        latest: params[:latest],
        inclusive: params[:inclusive],
        cursor: params[:cursor],
        limit: params[:limit] || 100
      })

      if error
        return { status: 400, body: { ok: false, error: error } }
      end

      build_response(messages, has_more, next_cursor)
    rescue => e
      INTERNAL_ERROR
    end
  end
end