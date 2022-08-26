require './lib/slack'

require './lib/slack_logger'
require './lib/slack_events_receiver'
require './lib/slack_rtm_receiver'

config = YAML.load_file('./config.yml')

receiver = Slack::Events.config.signing_secret ? SlackEventsReceiver.new(config['slack']['team_id']) : SlackRTMReceiver.new
SlackLogger.new.start receiver
