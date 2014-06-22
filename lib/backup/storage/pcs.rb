require 'base64'
require 'json'
require 'baidu/oauth'
require 'baidu/pcs'

module Backup
  module Storage
    class PCS < Base
      class Error < Backup::Error; end

      attr_accessor :client_id, :client_secret, :dir_name, :max_retries, :retry_waitsec

      def initialize(model, storage_id=nil)
        super

        @path          ||= 'backups'
        @max_retries   ||= 10
        @retry_waitsec ||= 30
      end

      private

      def transfer!
        package.filenames.each do |filename|
          src  = File.join(Config.tmp_path, filename)
          dest = File.join(remote_path, filename)
          Logger.info "Storing '#{ dest }'..."
          auto_refresh_token do
            File.open(src, 'r') do |file|
              options = {
                path:          dest,
                block_upload:  true,
                retry_times:   @max_retries,
                retry_waitsec: @retry_waitsec
              }
              client.upload file, options
            end
          end
        end
      rescue => err
        raise Error.wrap(err, 'Upload Failed!')
      end

      def remove!(package)
        Logger.info "Removing backup package dated #{ package.time }..."

        auto_refresh_token do
          client.delete(remote_path_for(package))
        end
      end

      # create or get Baidu PCS client
      def client
        return @client if @client

        unless session = cached_session
          Logger.info "Creating a new Baidu session!"
          session = create_session!
        end

        @client = Baidu::PCS::Client.new(session, dir_name)
      rescue => err
        raise Error.wrap(err, 'Authorization Failed.')
      end

      # cache Baidu::Session
      def cached_session
        session = false
        if File.exist?(cached_file)
          begin
            content = Base64.decode64(File.read(cached_file))
            session = Marshal.load(content)
            Logger.info "Baidu session data loaded from cache!"
          rescue => err
            Logger.warn Error.wrap(err, "Cached file: #{cached_file} might be corrupt.")
          end
        end
        session
      end

      def auto_refresh_token
        tries = 0
        begin
          yield
        rescue Baidu::Errors::AuthError, Errno::EPIPE => e
          raise Error, 'Too many auth errors' if (tries += 1) > 5
          Logger.info "Refreshing Baidu session..."
          session = oauth_client.refresh(cached_session.refresh_token)
          raise Error.wrap(e, 'Authorization Failed!') unless session
          write_cache! session
          @client = nil
          retry
        end
      end

      def cached_file
        File.join(Config.cache_path, "pcs_#{storage_id}_#{client_id}")
      end

      def write_cache!(session)
        FileUtils.mkdir_p(Config.cache_path)
        File.open(cached_file, "w") do |cache_file|
          cache_file.write(Base64.encode64(Marshal.dump(session)))
        end
      end

      def oauth_client
        Baidu::OAuth::Client.new(client_id, client_secret)
      end

      def create_session!
        require 'timeout'

        device_flow = oauth_client.device_flow
        rest = device_flow.user_and_device_code('netdisk')

        STDOUT.puts "1. Visit verification url: #{rest[:verification_url]}"
        STDOUT.puts "2. Type user code below in the form"
        STDOUT.puts "\t #{rest[:user_code]}"
        STDOUT.puts "3. Hit 'Enter/Return' once you're authorized."

        Timeout::timeout(300) { STDIN.gets }

        session = device_flow.get_token(rest[:device_code])

        write_cache!(session)
        STDOUT.puts "Baidu session cached: #{cached_file}"

        session
      rescue => err
        raise Error.wrap(err, 'Could not create a new session!')
      end
    end
  end
end
