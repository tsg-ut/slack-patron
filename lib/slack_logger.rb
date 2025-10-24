require './lib/slack'
require './lib/db'

class SlackLogger
  attr_reader :slack

  def initialize
    @slack = SlackPatron::SlackClient.new
  end

  def is_private_message(message)
    !message['channel_type'].nil? && message['channel_type'] != 'channel'
  end

  def is_tombstone(message)
    message['subtype'] == 'tombstone'
  end

  def skip_message?(message)
    is_private_message(message) || is_tombstone(message)
  end

  def new_message(message)
    return if skip_message?(message)
    if message['subtype'] == 'message_changed'
      new_message({
        **message['message'],
        'channel' => message['channel'],
      })
    else
      insert_message(message)
    end
  end

  def new_reaction(ts, name, user)
    add_reaction(ts, name, user)
  end

  def drop_reaction(ts, name, user)
    remove_reaction(ts, name, user)
  end

  def update_users
    users = slack.users_list
    replace_users(users)
  end

  def update_channels
    channels = slack.conversations_list
    replace_channels(channels)
  end

  def update_emojis
    emojis = slack.emoji_list
    replace_emojis(emojis)
  end

  def fetch_history(channel)
    begin
      messages = slack.conversations_history(channel, 15)
    rescue Slack::Web::Api::Errors::NotInChannel, Slack::Web::Api::Errors::ChannelNotFound
      return # どうしようもないね
    end
    return if messages.nil?

    messages.each do |m|
      m['channel'] = channel
      insert_message(m)
    end
  end

  def start(collector)
    begin
      collector_thread = Thread.new { collector.start!(self) }

      update_emojis
      update_users
      update_channels

      # カーソルのタイムアウトを避けるため、配列に変換してから処理
      Channels.find.to_a.each do |channel|
        # ループに時間がかかるので、毎回最新情報を確認する
        begin
          new_channel = slack.conversations_info(channel[:id])
        rescue Slack::Web::Api::Errors::SlackError => e
          puts "Failed to get channel info for #{channel[:id]}: #{e.message}"
          next
        end

        if new_channel.nil? || new_channel[:is_private]
          puts "skipping private or inaccessible channel #{channel[:id]}"
          next
        end

        puts "loading messages from #{new_channel[:name]}"
        # Note that conversations.history method is rate limited to 1 request per minute
        # https://api.slack.com/changelog/2025-05-terms-rate-limit-update-and-faq
        fetch_history new_channel[:id]
        sleep 120
      end

      # realtime event is joined and dont exit current thread
      collector_thread.join
    ensure
      collector_thread.kill
    end
  end
end
