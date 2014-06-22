# encoding: UTF-8

require 'backup/pcs'

module Backup
  describe Storage::PCS do
    let(:model)   { Model.new(:test_trigger, 'test label') }
    let(:storage) { Storage::PCS.new(model) }

    describe '#initialize' do
      it 'is a Storage::Base' do
        expect(storage).to be_a(Storage::Base)
      end

      it 'includes Storage::::Cycler' do
        expect(storage).to be_a(Storage::Cycler)
      end

      it 'has default config' do
        expect(storage.storage_id   ).to be_nil
        expect(storage.keep         ).to be_nil
        expect(storage.client_id    ).to be_nil
        expect(storage.client_secret).to be_nil
        expect(storage.dir_name     ).to be_nil
        expect(storage.path         ).to eq 'backups'
        expect(storage.cache_path   ).to eq '.cache'
        expect(storage.max_retries  ).to be 10
        expect(storage.retry_waitsec).to be 30
      end

      it 'inits with config' do
        storage = Storage::PCS.new(model, 'sid') do |c|
          c.keep          = 1
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.dir_name      = 'dn'
          c.path          = 'myback'
          c.cache_path    = '.mycache_path'
          c.max_retries   = 2
          c.retry_waitsec = 3
        end

        expect(storage.storage_id   ).to eq('sid')
        expect(storage.keep         ).to eq(1)
        expect(storage.client_id    ).to eq('ci')
        expect(storage.client_secret).to eq('cs')
        expect(storage.dir_name     ).to eq('dn')
        expect(storage.path         ).to eq 'myback'
        expect(storage.cache_path   ).to eq '.mycache_path'
        expect(storage.max_retries  ).to be(2)
        expect(storage.retry_waitsec).to be(3)
      end

      it 'inits with absolute cache path' do
        storage = Storage::PCS.new(model, 'sid') do |c|
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.cache_path    = '/tmp/pcs_tmp'
          c.dir_name      = 'dn'
          c.path          = 'myback'
        end

        expect(storage.cache_path).to eq '/tmp/pcs_tmp'
      end
    end

    describe '#transfer!' do
      let(:timestamp)   { Time.now.strftime("%Y.%m.%d.%H.%M.%S") }
      let(:remote_path) { File.join('myback/test_trigger', timestamp) }
      let(:package) { double }
      let(:file)    { double }
      let(:client)  { double }
      let(:cached_session) { double }
      let(:storage) {
        Storage::PCS.new(model, 'sid') do |c|
          c.keep          = 1
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.dir_name      = 'dn'
          c.path          = 'myback'
          c.max_retries   = 2
          c.retry_waitsec = 3
        end
      }

      before do
        allow(storage).to receive(:package).and_return(package)
        allow(package).to receive(:trigger).and_return('test_trigger')
        allow(package).to receive(:time).and_return(timestamp)
        allow(file).to    receive(:size).and_return(68*1024*1024)
        allow(storage).to receive(:client).and_return(client)
        allow(storage).to receive(:cached_session).and_return(cached_session)
      end

      it 'transfers files' do
        allow(client).to  receive(:upload)
        allow(package).to receive(:filenames).
          and_return(['test_trigger.tar_aa', 'test_trigger.tar_ab'])
        src  = File.join(Config.tmp_path, 'test_trigger.tar_aa')
        dest = File.join(remote_path, 'test_trigger.tar_aa')
        expect(File).to   receive(:open).with(src, 'r').and_yield(file)
        expect(client).to receive(:upload).with(file, path: dest, block_upload: true,
                                                                   retry_times: 2,
                                                                   retry_waitsec: 3)

        src  = File.join(Config.tmp_path, 'test_trigger.tar_ab')
        dest = File.join(remote_path, 'test_trigger.tar_ab')
        expect(File).to    receive(:open).with(src, 'r').and_yield(file)
        expect(client).to  receive(:upload).with(file, path: dest, block_upload: true,
                                                                   retry_times: 2,
                                                                   retry_waitsec: 3)
        expect(storage).to receive(:auto_refresh_token).and_yield.twice
        storage.send(:transfer!)
      end

      describe 'when access token expired' do
        let(:oauth_client) { double }
        let(:session) { double }

        before do
          allow(package).to  receive(:filenames).and_return(['test_trigger.tar_aa'])
          allow(client).to   receive(:upload).and_raise(Baidu::Errors::AuthError, 'expired')
          allow(storage).to  receive(:write_cache!).with(session) do
            allow(client).to receive(:upload).and_return(nil)  # do not raise like before
          end
          allow(storage).to        receive(:oauth_client).and_return(oauth_client)
          allow(cached_session).to receive(:refresh_token)
        end

        it 'refreshes access token automatically with valid refresh token' do
          allow(oauth_client).to receive(:refresh).and_return(session)

          src  = File.join(Config.tmp_path, 'test_trigger.tar_aa')
          dest = File.join(remote_path, 'test_trigger.tar_aa')
          expect(Logger).to receive(:info).with("Storing '#{dest}'...")
          expect(File).to   receive(:open).with(src, 'r').and_yield(file).twice
          expect(client).to receive(:upload).with(file, path: dest, block_upload: true,
                                                                   retry_times: 2,
                                                                   retry_waitsec: 3).twice
          expect(Logger).to receive(:info).with('Refreshing Baidu session...')
          storage.send(:transfer!)
        end

        it 'refreshes access token automatically with invalid refresh token' do
          allow(cached_session).to receive(:refresh_token).and_return(nil)
          allow(oauth_client).to   receive(:refresh).and_return(nil)

          src  = File.join(Config.tmp_path, 'test_trigger.tar_aa')
          dest = File.join(remote_path, 'test_trigger.tar_aa')
          expect(Logger).to       receive(:info).with("Storing '#{dest}'...")
          expect(File).to         receive(:open).with(src, 'r').and_yield(file).once
          expect(Logger).to       receive(:info).with('Refreshing Baidu session...')
          expect(oauth_client).to receive(:refresh)
          expect(Kernel).to       receive(:raise)
          expect(storage).to      receive(:write_cache!).never
          expect {
            storage.send(:transfer!)
          }.to raise_error(Storage::PCS::Error)
        end
      end
    end

    describe '#remove!' do
      let(:timestamp)   { Time.now.strftime("%Y.%m.%d.%H.%M.%S") }
      let(:remote_path) { File.join('myback/test_trigger', timestamp) }
      let(:package) { double }
      let(:client)  { double }
      let(:storage) {
        Storage::PCS.new(model, 'sid') do |c|
          c.keep          = 1
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.dir_name      = 'dn'
          c.path          = 'myback'
          c.max_retries   = 2
          c.retry_waitsec = 3
        end
      }

      before do
        allow(storage).to receive(:package).and_return(package)
        allow(package).to receive(:trigger).and_return('test_trigger')
        allow(package).to receive(:time).and_return(timestamp)
        allow(storage).to receive(:client).and_return(client)
      end

      it 'removes package' do
        expect(Logger).to receive(:info).with("Removing backup package dated #{ timestamp }...")
        expect(client).to receive(:delete).with(remote_path)

        storage.send(:remove!, package)
      end
    end

    describe '#client' do
      let(:storage) {
        Storage::PCS.new(model, 'sid') do |c|
          c.keep          = 1
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.dir_name      = 'dn'
          c.path          = 'myback'
          c.max_retries   = 2
          c.retry_waitsec = 3
        end
      }

      it 'creates new session' do
        session = double
        client  = double
        allow(storage).to receive(:cached_session).and_return(nil)
        allow(storage).to receive(:create_session!).and_return(session)
        allow(Baidu::PCS::Client).to receive(:new).with(session, 'dn').and_return(client)

        expect(Logger).to  receive(:info).with('Creating a new Baidu session!')
        expect(storage).to receive(:create_session!).once.and_return(session)

        storage.send(:client)
        expect(storage.instance_variable_get(:@client)).to eq(client)
      end

      it 'uses cached session' do
        session = double
        client  = double
        allow(storage).to receive(:cached_session).and_return(session)
        allow(Baidu::PCS::Client).to receive(:new).with(session, 'dn').and_return(client)

        expect(storage).to receive(:create_session!).never

        storage.send(:client)
        expect(storage.instance_variable_get(:@client)).to eq(client)
      end
    end

    describe '#cached_session' do
      let(:storage) {
        Storage::PCS.new(model, 'sid') do |c|
          c.keep          = 1
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.dir_name      = 'dn'
          c.path          = 'myback'
          c.max_retries   = 2
          c.retry_waitsec = 3
        end
      }

      it 'has no cached file' do
        expect(File).to receive(:exist?).and_return(false)
        expect(storage.send(:cached_session)).to eq(false)
      end

      it 'loads cached session' do
        session = double
        content = double
        base64_c = double
        cached_file = storage.send(:cached_file)
        expect(File).to    receive(:exist?).with(cached_file).and_return(true)
        expect(File).to    receive(:read).with(cached_file).and_return(content)
        expect(Base64).to  receive(:decode64).with(content).and_return(base64_c)
        expect(Marshal).to receive(:load).with(base64_c).and_return(session)
        expect(Logger).to  receive(:info).with('Baidu session data loaded from cache!')

        expect(storage.send(:cached_session)).to eq(session)
      end

      it 'loads cached session failed' do
        expect(File).to    receive(:exist?).and_return(true)
        expect(File).to    receive(:read).and_raise('error.')
        expect(Logger).to  receive(:warn)
        expect(storage.send(:cached_session)).to eq(false)
      end
    end

    describe '#auto_refresh_token' do
      let(:session) { double }
      let(:oauth_client) { double }
      let(:cached_session) { double }
      let(:storage) {
        Storage::PCS.new(model, 'sid') do |c|
          c.keep          = 1
          c.client_id     = 'ci'
          c.client_secret = 'cs'
          c.dir_name      = 'dn'
          c.path          = 'myback'
          c.max_retries   = 2
          c.retry_waitsec = 3
        end
      }

      before do
        allow(storage).to receive(:oauth_client).and_return(oauth_client)
        allow(storage).to receive(:cached_session).and_return(cached_session)
        allow(cached_session).to receive(:refresh_token)
      end

      it 'does not raise autu error' do
        expect(Logger).to       receive(:info).with('Refreshing Baidu session...').never
        expect(oauth_client).to receive(:refresh).never
        expect(storage).to      receive(:write_cache!).never

        storage.send(:auto_refresh_token) { }
      end

      it 'raises auth error with valid refresh token' do
        work_p = proc { raise Baidu::Errors::AuthError, 'expired' }
        allow(oauth_client).to receive(:refresh).and_return(session)
        allow(storage).to receive(:write_cache!) do
          work_p = proc { }
        end

        expect(Logger).to       receive(:info).with('Refreshing Baidu session...')
        expect(oauth_client).to receive(:refresh)
        expect(storage).to      receive(:write_cache!).with(session)

        storage.send(:auto_refresh_token) { work_p.call }
      end

      it 'raises auth error with invalid refresh token' do
        work_p = proc { raise Baidu::Errors::AuthError, 'expired' }
        allow(oauth_client).to receive(:refresh).and_return(nil)
        allow(storage).to receive(:write_cache!) do
          work_p = proc { }
        end

        expect(Logger).to       receive(:info).with('Refreshing Baidu session...')
        expect(oauth_client).to receive(:refresh)
        expect(storage).to      receive(:write_cache!).never

        expect {
          storage.send(:auto_refresh_token) { work_p.call }
        }.to raise_error(Storage::PCS::Error)
      end

      it 'closes connection when uploading file' do
        work_p = proc { raise Errno::EPIPE }
        allow(oauth_client).to receive(:refresh).and_return(session)
        allow(storage).to receive(:write_cache!) do
          work_p = proc { }
        end

        expect(Logger).to       receive(:info).with('Refreshing Baidu session...')
        expect(oauth_client).to receive(:refresh)
        expect(storage).to      receive(:write_cache!).with(session)

        storage.send(:auto_refresh_token) { work_p.call }
      end

      it 'raises when there are too many auth errors' do
        work_p = proc { raise Baidu::Errors::AuthError, 'expired' }
        allow(oauth_client).to receive(:refresh).and_return(session)
        expect {
          storage.send(:auto_refresh_token) { work_p.call }
        }.to raise_error(Storage::PCS::Error, 'Storage::PCS::Error: Too many auth errors')
      end
    end

    describe '#cached_file' do
      it 'has right cached file path' do
        path1 = Storage::PCS.new(model, 'sid') do |c|
          c.client_id = 'ci'
        end.send(:cached_file)
        expect(path1).to eq("#{Config.root_path}/.cache/pcs_sid_ci")

        path2 = Storage::PCS.new(model) do |c|
          c.client_id  = 'ci2'
          c.cache_path = '/tmp/pcs'
        end.send(:cached_file)
        expect(path2).to eq('/tmp/pcs/pcs__ci2')
      end
    end

    describe '#write_cache!' do
      let(:cached_file) { double }
      let(:session) { double }

      before do
        storage.client_id = 'ci'
        allow(File).to receive(:dirname).and_return(File.join(Config.root_path, '.cache'))
        allow(FileUtils).to receive(:mkdir_p)
        allow(storage).to receive(:cached_file).and_return(cached_file)
      end

      it 'writes cached file' do
        expect(FileUtils).to receive(:mkdir_p).with(File.join(Config.root_path, '.cache'))
        expect(File).to receive(:open).with(cached_file, 'w').and_yield(cached_file)
        data = Base64.encode64(Marshal.dump(session))
        expect(cached_file).to receive(:write).with(data)

        storage.send(:write_cache!, session)
      end
    end

    describe '#oauth' do
      before do
        storage.client_id = 'ci'
        storage.client_secret = 'cs'
      end

      it 'creates oauth client' do
        oclient = double
        expect(Baidu::OAuth::Client).to receive(:new).with('ci', 'cs').and_return(oclient)
        expect(storage.send(:oauth_client)).to eq(oclient)
      end
    end

    describe '#create_session!' do
      let(:rest) { Hash.new }
      before do
        storage.client_id = 'ci'
        storage.client_secret = 'cs'
      end

      it 'is authorized successfully' do
        device_flow = double
        oauth_client = double
        session = double
        expect(storage).to receive(:oauth_client).and_return(oauth_client)
        expect(oauth_client).to receive(:device_flow).and_return(device_flow)
        expect(device_flow).to receive(:user_and_device_code).with('netdisk').and_return(rest)

        rest[:verification_url] = 'https://example.com/verification_url'
        rest[:user_code]        = 'xxxyyy'
        rest[:device_code]      = 'zzzzzz'

        expect(STDOUT).to receive(:puts).with('1. Visit verification url: https://example.com/verification_url')
        expect(STDOUT).to receive(:puts).with('2. Type user code below in the form')
        expect(STDOUT).to receive(:puts).with("\t xxxyyy")
        expect(STDOUT).to receive(:puts).with("3. Hit 'Enter/Return' once you're authorized.")
        expect(STDIN).to  receive(:gets)
        expect(STDOUT).to receive(:puts).with('Baidu session cached: ' + storage.send(:cached_file))

        expect(device_flow).to receive(:get_token).with(rest[:device_code]).and_return(session)
        expect(storage).to     receive(:write_cache!).with(session)

        expect(storage.send(:create_session!)).to eq(session)
      end

      it 'is not authorized' do
        allow(storage).to receive(:oauth_client).and_raise('any error')
        expect {
          storage.send(:create_session!)
        }.to raise_error(Storage::PCS::Error)
      end
    end
  end
end
