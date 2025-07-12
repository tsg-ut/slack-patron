require './lib/api_helpers'
require './lib/db'

# API module that aims to mimic Slack's API endpoint
module SlackApi
  extend self

  def conversations_history_query(params)
    limit = [params[:limit].to_i, 1000].min
    limit = 100 if limit <= 0

    channel = params[:channel]
    oldest = params[:oldest]
    latest = params[:latest]
    inclusive = params[:inclusive] == 'true' || params[:inclusive] == '1'
    cursor = params[:cursor]

    # Decode cursor for pagination
    cursor_direction, cursor_ts = ApiHelpers.decode_cursor(cursor)

    conditions = [
      { '$or' => [{ hidden: { '$ne' => true } }, { subtype: 'tombstone' }] },
      { channel: channel },
      # Exclude thread-only messages
      {
        '$or' => [
          { thread_ts: { '$exists' => false } },  # No thread_ts field
          { thread_ts: nil },                     # thread_ts is null
          { '$expr' => { '$eq' => ['$thread_ts', '$ts'] } },  # thread_ts equals ts (thread parent)
          { subtype: 'thread_broadcast' }         # thread_broadcast messages should be shown
        ]
      }
    ]

    # Apply timestamp filters
    if oldest && ApiHelpers.validate_timestamp(oldest)
      operator = inclusive ? '$gte' : '$gt'
      conditions << { ts: { operator => oldest } }
    end

    if latest && ApiHelpers.validate_timestamp(latest)
      operator = inclusive ? '$lte' : '$lt'
      conditions << { ts: { operator => latest } }
    end

    # Apply cursor-based pagination
    if cursor_ts && ApiHelpers.validate_timestamp(cursor_ts)
      if cursor_direction == 'before'
        conditions << { ts: { '$lt' => cursor_ts } }
      elsif cursor_direction == 'after'
        conditions << { ts: { '$gt' => cursor_ts } }
      end
    end

    # Query messages
    all_messages = Messages
      .find({ '$and' => conditions })
      .sort(ts: -1)  # Most recent first, as per Slack API
      .limit(limit + 1)  # Get one extra to check for has_more
      .to_a

    has_more = all_messages.length > limit
    return_messages = all_messages.first(limit)

    # Generate next cursor if there are more messages
    next_cursor = nil
    if has_more && !return_messages.empty?
      last_ts = return_messages.last['ts']
      next_cursor = ApiHelpers.encode_cursor(last_ts, 'before')
    end

    # Transform messages to match Slack API format
    slack_messages = return_messages.map do |msg|
      ApiHelpers.transform_message_to_slack_format(msg)
    end

    return slack_messages, has_more, next_cursor
  end

  def conversations_history_response(params)
    # Validate required parameters
    unless params[:channel] && ApiHelpers.validate_channel_id(params[:channel])
      return { status: 400, body: { ok: false, error: 'channel_not_found' } }
    end

    # Validate optional timestamp parameters
    if params[:oldest] && !ApiHelpers.validate_timestamp(params[:oldest])
      return { status: 400, body: { ok: false, error: 'invalid_ts_oldest' } }
    end

    if params[:latest] && !ApiHelpers.validate_timestamp(params[:latest])
      return { status: 400, body: { ok: false, error: 'invalid_ts_latest' } }
    end

    # Validate cursor
    if params[:cursor]
      direction, ts = ApiHelpers.decode_cursor(params[:cursor])
      if direction.nil? || ts.nil?
        return { status: 400, body: { ok: false, error: 'invalid_cursor' } }
      end
    end

    begin
      messages, has_more, next_cursor = conversations_history_query({
        channel: params[:channel],
        oldest: params[:oldest],
        latest: params[:latest],
        inclusive: params[:inclusive],
        cursor: params[:cursor],
        limit: params[:limit] || 100
      })

      response = {
        ok: true,
        messages: messages,
        has_more: has_more,
        pin_count: 0  # Not implemented
      }

      # Add response_metadata with next_cursor if pagination is needed
      if next_cursor
        response[:response_metadata] = {
          next_cursor: next_cursor
        }
      end

      # Add latest timestamp if it was provided in the request
      response[:latest] = params[:latest] if params[:latest]

      { status: 200, body: response }
    rescue => e
      { status: 500, body: { ok: false, error: 'internal_error' } }
    end
  end
end