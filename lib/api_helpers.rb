require 'base64'
require './lib/db'

module ApiHelpers
  extend self

  def encode_cursor(ts, direction = 'before')
    Base64.encode64("#{direction}:#{ts}").strip
  end

  def decode_cursor(cursor)
    return nil, nil if cursor.nil? || cursor.empty?
    decoded = Base64.decode64(cursor)
    parts = decoded.split(':', 2)
    return nil, nil if parts.length != 2
    [parts[0], parts[1]]
  rescue
    [nil, nil]
  end

  def validate_channel_id(channel)
    return false if channel.nil? || channel.empty?
    # Basic validation for Slack channel ID format
    channel.match?(/^[CDG][A-Z0-9]{8,10}$/) || channel.match?(/^[CDG][A-Z0-9]{8,10}[A-Z0-9]*$/)
  end

  def validate_timestamp(ts)
    return false if ts.nil? || ts.empty?
    # Validate Slack timestamp format (Unix timestamp with microsecond precision)
    ts.match?(/^\d+\.\d+$/)
  end

  def transform_message_to_slack_format(msg)
    msg = normalize_message(msg)

    slack_msg = {
      'type' => msg['type'] || 'message',
      'ts' => msg['ts']
    }

    # Add user field
    slack_msg['user'] = msg['user'] if msg['user']
    slack_msg['bot_id'] = msg['bot_id'] if msg['bot_id']

    # Add text field
    slack_msg['text'] = msg['text'] if msg['text']

    # Add thread info
    slack_msg['thread_ts'] = msg['thread_ts'] if msg['thread_ts']
    slack_msg['reply_count'] = msg['reply_count'] if msg['reply_count']

    # Add subtype
    slack_msg['subtype'] = msg['subtype'] if msg['subtype']

    # Add attachments
    slack_msg['attachments'] = msg['attachments'] if msg['attachments']

    # Add files
    slack_msg['files'] = msg['files'] if msg['files']

    # Add reactions
    slack_msg['reactions'] = msg['reactions'] if msg['reactions']

    # Add edited info
    slack_msg['edited'] = msg['edited'] if msg['edited']

    # Add any other Slack-specific fields that might exist
    %w[username bot_profile app_id team blocks].each do |field|
      slack_msg[field] = msg[field] if msg[field]
    end

    slack_msg
  end
end