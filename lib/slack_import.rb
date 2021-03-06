require 'json'
require 'zip'
require 'fileutils'
require 'tmpdir'
require './lib/db'

class SlackImport
  def import_messages(channel, messages)
    messages.each do |m|
      m['channel'] = channel[:id]
      insert_message(m)
    end
  end

  def import_channels(channels)
    replace_channels(channels)
  end

  def import_users(users)
    replace_users(users)
  end

  # format of exported file
  #
  # exported.zip
  #
  # - channels.json
  # - users.json
  # - channel/
  #     - 2015-01-01.json
  def import_from_file(exported_file)
    dist = Dir.mktmpdir
    begin
      Zip::File.open(exported_file) do |zip|
        zip.each do |entry|
          entry.extract(dist + '/' + entry.to_s)
        end
        open(dist + '/channels.json') do |io|
          import_channels(JSON.load(io))
        end
        open(dist + '/users.json') do |io|
          import_users(JSON.load(io))
        end
        zip.each do |entry|
          # channel/2015-01-01.json
          file_name = entry.name.clone.force_encoding('UTF-8')
          if !File.directory?(dist + '/' + file_name) and file_name.split('/').size > 1
            puts "import #{file_name}"
            channel = Channels.find(name: file_name.split('/')[0]).to_a[0]
            messages = JSON.load(entry.get_input_stream)
            import_messages(channel, messages)
          end
        end
      end
    ensure
      FileUtils.rm_r(dist)
    end
  end
end
