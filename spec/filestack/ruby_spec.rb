require 'spec_helper'
require './lib/filestack'
require 'filestack/config'
require 'filestack/mixins/filestack_common'
require 'filestack/utils/multipart_upload_utils'
require 'filestack/utils/utils'

include MultipartUploadUtils
include UploadUtils
include FilestackCommon

class Response
  def initialize(error_number = nil)
    @code = error_number || 200
  end

  def body
    'thisissomecontent'
  end

  def code
    @code
  end
end

class GeneralResponse
  attr_reader :body, :code

  def initialize(body_content, error_number = 200)
    @code = error_number
    @body = body_content
  end

  def code
    @code
  end
end


RSpec.describe Filestack::Ruby do
  before(:each) do
    @test_handle = 'V059dRmSeWHT5WbiXssg'
    @test_apikey = 'YOUR_API_KEY'
    @test_secret = 'YOUR_SECRET'
    @test_filepath = __dir__ + '/../../test-files/calvinandhobbes.jpg'
    @test_download =  __dir__ + '/../../test-files/test'
    @test_filename = 'calvinandhobbes.jpg'
    @test_filesize = 10000
    @test_mimetype = 'image/jpeg'
    @start_response = {
      'uri' => 'uri',
      'region' => 'region',
      'upload_id' => 'upload_id',
      'location_url' => 'location_url',
      'upload_type' => 'not_intelligent'
    }
    @intelligent_start_response = {
      'uri' => 'uri',
      'region' => 'region',
      'upload_id' => 'upload_id',
      'location_url' => 'location_url',
      'upload_type' => 'intelligent_ingestion'
    }
    @job = {
      seek: 0,
      filepath: @test_filepath,
      filename: @test_filename,
      apikey: @test_apikey,
      part: 1,
      uri: @start_response[:uri],
      region: @start_response[:region],
      upload_id: @start_response[:upload_id],
      location_url: @start_response[:location_url]
    }
    @response = Response.new
    @test_client = FilestackClient.new(@test_apikey)
    @test_filelink = FilestackFilelink.new(@test_handle)
    @test_security = FilestackSecurity.new(@test_secret)
    @test_secure_client = FilestackClient.new(@test_apikey, security: @test_security)
    @test_secure_filelink = FilestackFilelink.new(@test_apikey, security: @test_security)
    @test_transform = Transform.new(apikey: @test_apikey, handle: @test_handle, security: @test_security)
  end

  it 'has a version number' do
    expect(Filestack::Ruby::VERSION).not_to be nil
  end

  it 'Filesecurity.generate called successfully' do
    mock_hash = 'some-hash-value'
    mock_signature = 'some-signature-hash-value'

    allow(Base64).to receive(:urlsafe_encode64).and_return(mock_hash)
    allow(OpenSSL::HMAC).to receive(:hexdigest).and_return(mock_signature)

    options = { 'expiry' => 3600 }
    security = FilestackSecurity.new(@test_secret)
    security.generate(@test_secret, options)

    expect(security.policy).to eq(mock_hash)
    expect(security.signature).to eq(mock_signature)
  end

  it 'Filesecurity.sign_url called successfully' do
    security = FilestackSecurity.new(@test_secret)
    test_url = 'http://example-test.com'
    signed_url = security.sign_url(test_url)

    expect(signed_url).to include(test_url)
    expect(signed_url).to include('policy=')
    expect(signed_url).to include('signature=')
  end

  it 'FilestackFilelink makes correct url' do
    expect(@test_secure_filelink.url)
  end

  it 'FilestackFilelink uploads without multipart' do
    class UploadResponse
      def code
        200
      end

      def body
        {'url' => 'https://cdn.filestackcontent.com/somehandle'}
      end
    end
    allow(Unirest).to receive(:post)
      .and_return(UploadResponse.new)
    filelink = @test_secure_client.upload(filepath: @test_filepath, multipart: false)
    expect(filelink.handle).to eq('somehandle')
  end

  it 'FilestackFilelink uploads external without multipart' do
    class UploadResponse
      def code
        200
      end

      def body
        {'url' => 'https://cdn.filestackcontent.com/somehandle'}
      end
    end
    allow(Unirest).to receive(:post)
      .and_return(UploadResponse.new)
    filelink = @test_secure_client.upload(external_url: @test_filepath, multipart: false)
    expect(filelink.handle).to eq('somehandle')
  end

  it 'Does not upload when both url and filepath are present' do
    bad = @test_secure_client.upload(filepath: @test_filepath, external_url: 'someurl', multipart: false)
    expect(bad).to eq('You cannot upload a URL and file at the same time')
  end

  it 'zips corectly' do
    allow(Unirest).to receive(:get)
      .and_return(GeneralResponse.new('somebytes'))
    @test_client.zip('test-files/test.zip', ["https://www.example.com","https://www.example.com"])
  end

  ######################
  ## MULTIPART TESTING #
  ######################

  it 'returns the right file info' do
    allow(File).to receive(:basename).and_return(@test_filename)
    allow(File).to receive(:size).and_return(@test_filesize)

    filename, filesize, mimetype =
      MultipartUploadUtils.get_file_info(@test_filepath)

    expect(filename).to eq(@test_filename)
    expect(filesize).to eq(@test_filesize)
    expect(mimetype).to eq(@test_mimetype)
  end

  it 'returns the correct multipart_start response' do
    allow(Unirest).to receive(:post)
      .and_return(@response)

    response = MultipartUploadUtils.multipart_start(
      @test_apikey, @test_filename, @test_filesize,
      @start_response, @test_security, nil
    )
    expect(response).to eq('thisissomecontent')
  end

  it 'returns the correct create_upload_jobs array' do
    jobs = create_upload_jobs(
      @test_apikey, @test_filename, @test_filepath,
      @test_filesize, @start_response, nil
    )
    expect(jobs[0][:filepath]).to eq(@test_filepath)
  end

  it 'returns correct upload_chunk response' do
    class FilestackResponse
      def body
        {
          url: 'someurl',
          headers: 'seomheaders'
        }
      end
    end
    allow(Unirest).to receive(:post).and_return(FilestackResponse.new)
    allow(Unirest).to receive(:put)
      .and_return(@response)

    response = MultipartUploadUtils.upload_chunk(
      @job, @test_apikey, @test_filepath, nil
    )
    expect(response.body).to eq('thisissomecontent')
  end

  it 'returns the correct parallel results' do
    class HeadersResponse
      def headers
        { etag: 'someetag' }
      end

      def code
        200
      end
    end

    jobs = []
    2.times do
      jobs.push(@job)
    end
    part = @job[:part]
    result_string = "#{part}:someetag"

    allow(MultipartUploadUtils).to receive(:upload_chunk)
      .and_return(HeadersResponse.new)
    target_results = []
    2.times do
      target_results.push(result_string)
    end

    results = MultipartUploadUtils.run_uploads(
      jobs, @test_apikey, @test_filepath, nil
    )
    2.times do |i|
      expect(results[i]).to eq(result_string)
    end
  end

  it 'returns the correct multipart_complete response' do
    allow(Unirest).to receive(:post).and_return(@response)
    response = MultipartUploadUtils.multipart_complete(
      @test_apikey, @test_filename, @test_filesize, @test_mimetype,
      @start_response, %w[somepartsandetags somepartsandetags], nil
    )
    expect(response.body).to eq(@response.body)
  end

  it 'Multipart upload returns the correct response' do
    allow(MultipartUploadUtils).to receive(:multipart_upload)
      .and_return(@response)
    response = MultipartUploadUtils.multipart_upload(
      @test_apikey, @test_filepath
    )
    expect(response.body).to eq(@response.body)
  end

  it 'runs multipart uploads' do
    allow_any_instance_of(MultipartUploadUtils).to receive(:multipart_start)
      .and_return(@start_response)
    allow_any_instance_of(MultipartUploadUtils).to receive(:run_uploads)
      .and_return(['somepartsandetags'])
    allow_any_instance_of(MultipartUploadUtils).to receive(:multipart_complete)
      .and_return(GeneralResponse.new({'handle' => 'somehandle'}))
    filelink = @test_client.upload(filepath: @test_filepath)
  end

  ##############################
  ## INTELLIGENT UTILS TESTING #
  ##############################

  it 'runs intelligent multipart uploads' do
    allow_any_instance_of(MultipartUploadUtils).to receive(:multipart_start)
      .and_return(@intelligent_start_response)
    allow_any_instance_of(IntelligentUtils).to receive(:run_intelligent_upload_flow)
      .and_return(true)
    allow_any_instance_of(MultipartUploadUtils).to receive(:multipart_complete)
      .and_return(GeneralResponse.new({'handle' => 'somehandle'}))
    filelink = @test_client.upload(filepath: @test_filepath, intelligent: true)
    expect(filelink.handle).to eq('somehandle')
  end

  it 'intelligent uploads fails upon 202 timeout' do
    allow_any_instance_of(MultipartUploadUtils).to receive(:multipart_start)
      .and_return(@intelligent_start_response)
    allow_any_instance_of(IntelligentUtils).to receive(:run_intelligent_upload_flow)
      .and_return(true)
    allow_any_instance_of(MultipartUploadUtils).to receive(:multipart_complete)
      .and_return(GeneralResponse.new({'handle' => 'somehandle'}, 202))
    expect{@test_client.upload(filepath: @test_filepath, intelligent: true, timeout: 1)}.to raise_error(RuntimeError)
  end

  it 'creates a batch of jobs' do
    jobs = []

    4.times do
      jobs.push([])
    end

    generator = IntelligentUtils.create_intelligent_generator(jobs)
    batch = get_generator_batch(generator)
    expect(batch.length).to eq(4)
  end

  it 'runs intelligent upload flow without failure' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    allow(IntelligentUtils).to receive(:run_intelligent_uploads)
      .and_return(state)

    IntelligentUtils.run_intelligent_upload_flow(jobs, state)
    expect(true)
  end

  it 'runs intelligent upload flow with failure' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    state.ok = false
    jobs = MultipartUploadUtils.create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    allow(IntelligentUtils).to receive(:run_intelligent_uploads)
      .and_return(state)

    expect {IntelligentUtils.run_intelligent_upload_flow(jobs, state)}.to raise_error(RuntimeError)
  end

  it 'runs intelligent uploads without error' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    allow(IntelligentUtils).to receive(:upload_chunk_intelligently)
      .and_return(state)
    allow(Unirest).to receive(:post)
      .and_return(@response)

    state = IntelligentUtils.run_intelligent_uploads(jobs[0], state)
    expect(state.ok)
  end

  it 'runs intelligent uploads with failure error' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    allow(IntelligentUtils).to receive(:upload_chunk_intelligently)
      .and_raise('FAILURE')

    state = IntelligentUtils.run_intelligent_uploads(jobs[0], state)
    expect(state.ok).to eq(false)
    expect(state.error_type).to eq('FAILURE')
  end

  it 'retries upon failure' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    state.ok = false
    state.error_type = 'BACKEND_SERVER'
    allow_any_instance_of(IntelligentUtils).to receive(:run_intelligent_uploads)
      .and_return(state)
    expect {IntelligentUtils.run_intelligent_upload_flow(jobs, state)}.to raise_error
  end

  it 'retries upon network failure' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    state.ok = false
    state.error_type = 'S3_NETWORK'
    allow_any_instance_of(IntelligentUtils).to receive(:run_intelligent_uploads)
      .and_return(state)
    expect {IntelligentUtils.run_intelligent_upload_flow(jobs, state)}.to raise_error
  end

  it 'retries upon server failure' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    state.ok = false
    state.error_type = 'S3_SERVER'
    allow_any_instance_of(IntelligentUtils).to receive(:run_intelligent_uploads)
      .and_return(state)
    expect {IntelligentUtils.run_intelligent_upload_flow(jobs, state)}.to raise_error
  end

  it 'retries upon backend network failure' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    state.ok = false
    state.error_type = 'BACKEND_NETWORK'
    allow_any_instance_of(IntelligentUtils).to receive(:run_intelligent_uploads)
      .and_return(state)
    expect {IntelligentUtils.run_intelligent_upload_flow(jobs, state)}.to raise_error
  end

  it 'runs intelligent uploads with 400 error' do
    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )
    allow(IntelligentUtils).to receive(:upload_chunk_intelligently)
      .and_return(true)
    allow(Unirest).to receive(:post)
      .and_return(Response.new(400))

    state = IntelligentUtils.run_intelligent_uploads(jobs[0], state)
    expect(state.ok).to eq(false)
  end

  it 'uploads chunk intelligently' do
    class FilestackResponse
      def body
        {
          url: 'someurl',
          headers: 'someheaders'
        }
      end

      def code
        200
      end
    end

    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )

    allow(Unirest).to receive(:post)
      .and_return(FilestackResponse.new)
    allow(Unirest).to receive(:put)
      .and_return(@response)
    jobs[0][:offset] = 0
    response = IntelligentUtils.upload_chunk_intelligently(jobs[0], state, @test_apikey, @test_filepath, {})
    expect(response.code).to eq(200)
  end

   it 'catches failure' do
    class FilestackResponse
      def body
        {
          url: 'someurl',
          headers: 'someheaders'
        }
      end

      def code
        200
      end
    end

    state = IntelligentState.new
    filename, filesize, mimetype = MultipartUploadUtils.get_file_info(@test_filepath)
    jobs = create_upload_jobs(
      @test_apikey, filename, @test_filepath, filesize, @start_response, {}
    )

    allow(Unirest).to receive(:post)
      .and_return(FilestackResponse.new)
    allow(Unirest).to receive(:put)
      .and_return(Response.new(400))
    jobs[0][:offset] = 0
    expect {IntelligentUtils.upload_chunk_intelligently(jobs[0], state, @test_apikey, @test_filepath, {})}.to raise_error(RuntimeError)
  end


  #########################
  ## COMMON MIXIN TESTING #
  #########################

  it 'gets contents of a filelink' do
    allow(UploadUtils).to receive(:make_call)
      .and_return(@response.body)
    content = @test_filelink.get_content
    expect(content).to eq(@response.body)
  end

  it 'downloads a filelink' do
    allow(UploadUtils).to receive(:make_call)
      .and_return(@response)

    response = @test_filelink.download(@test_download)
    expect(response).to eq(@response.body.length)
    File.delete(@test_download)
  end

  it 'deletes a filelink' do
    allow(UploadUtils).to receive(:make_call)
      .and_return(@response)

    delete = @test_secure_filelink.delete()
    expect(delete.body).to eq(@response.body)
  end

  it 'does not delete an unsecure filelink' do
    bad = @test_filelink.delete
    expect(bad).to eq('Delete requires security')
  end

  it 'overwrites a filelink' do
    allow(UploadUtils).to receive(:make_call)
      .and_return(@response)
    overwrite = @test_secure_filelink.overwrite(@test_filepath)
    expect(overwrite.body).to eq(@response.body)
  end

  it 'does not ovewrite an unsecure filelink' do
    bad = @test_filelink.overwrite(@test_filepath)
    expect(bad).to eq('Overwrite requires security')
  end

  it 'gets metadata' do
    allow(UploadUtils).to receive(:make_call)
      .and_return(GeneralResponse.new({data: 'data'}))
    metadata = @test_filelink.metadata
    expect(metadata[:data]).to eq('data')
  end

  it 'gets metadata with security' do
    allow(UploadUtils).to receive(:make_call)
      .and_return(GeneralResponse.new({data: 'data'}))
    metadata = @test_secure_filelink.metadata
    expect(metadata[:data]).to eq('data')
  end

  ###################
  ## TRANFORM TESTS #
  ###################

  it 'calls the correct transform methods' do
    TransformConfig::TRANSFORMATIONS.each do |transformation|
      @test_transform.public_send(transformation, width: 100, height: 100)
    end
  end

  it 'does not call the wrong transform method' do
    expect {
      lambda @test_transform.wrong_transformation(width: 100, height: 100)
    }.to raise_error(NoMethodError)
  end

  it 'creates AV class' do
    class AVresponse
      def body
        { 'status' => 'completed',
          'data' => {
            'url' => 'https://cdn.filestackcontent.com/somehandle'
          } }
      end
    end
    allow(Unirest).to receive(:post).and_return(@response)
    allow(Unirest).to receive(:get).and_return(AVresponse.new)
    av = @test_transform.av_convert(width: 100, height: 100)
    expect(av.status).to eq('completed')
    expect(av.to_filelink.handle).to eq('somehandle')
  end

  it 'does not create AV from external url' do
    av = Transform.new(external_url: 'someexternal_url')
    bad = av.av_convert(width: 100, height: 100)
    expect(bad).to eq('av_convert does not support external URLs. Please upload file first.')
  end

  it 'stores a transformation url' do
    transform_content = { 'url' => 'https://cdn.filestack.com/somehandle' }
    allow(Unirest).to receive(:get)
      .and_return(GeneralResponse.new(transform_content))
    expect(@test_transform.store.handle).to eq('somehandle')
  end

  it 'returns a debug object' do
    debug_content = { 'metadata' => { 'width' => 500 } }
    allow(Unirest).to receive(:get)
      .and_return(GeneralResponse.new(debug_content))
    debug = @test_transform.resize(width: 100).debug
    expect(debug['metadata']['width']).to eq(500)
  end

  it 'returns a transform with external URL' do
    transform = @test_client.transform_external('http://someurl.com')
    expect(transform.url).to eq("https://cdn.filestackcontent.com/#{@test_apikey}/http://someurl.com")
  end

  ###############
  ## TAGS TESTS #
  ###############

  it 'returns tags' do
    tag_content = { 'tags' => { 'tag' => 'sometag' } }
    allow(Unirest).to receive(:get).and_return(GeneralResponse.new(tag_content))
    tags = @test_secure_filelink.tags
    expect(tags['tag']).to eq('sometag')
  end

  it 'returns sfw' do
    sfw_content = { 'sfw' => { 'sfw' => 'true' } }
    allow(Unirest).to receive(:get).and_return(GeneralResponse.new(sfw_content))
    sfw = @test_secure_filelink.sfw
    expect(sfw['sfw']).to eq('true')
  end
end
