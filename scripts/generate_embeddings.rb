require "net/http"
require "json"
require "uri"

EMBEDDINGS_DIR = File.join(__dir__, "../examples/embeddings")
EXAMPLES_DIR = File.join(__dir__, "../examples")

# Define the API endpoint
uri = URI.parse("https://api.openai.com/v1/embeddings")

# Define the request
request = Net::HTTP::Post.new(uri)
request.content_type = "application/json"
request["Authorization"] = "Bearer #{ENV["OPENAI_API_KEY"]}"
Dir
  .glob("#{EXAMPLES_DIR}/*.txt")
  .each do |file|
    description = File.open(file, &:readline).strip

    sha = Digest::SHA256.hexdigest(description)

    embed_filename = "embeddings/#{File.basename(file, ".txt")}.json"

    existing_sha =
      begin
        JSON.parse(File.read(embed_filename))["sha"]
      rescue StandardError
        nil
      end

    if existing_sha == sha
      puts "Embedding for #{file} already exists. Skipping..."
    else
      puts "Generating embedding for #{file}..."

      request.body =
        JSON.dump(
          { "input" => description, "model" => "text-embedding-ada-002" }
        )

      response =
        Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https"
        ) { |http| http.request(request) }

      File.open(embed_filename, "w") do |f|
        f.write(
          JSON.pretty_generate(
            JSON.parse(response.body).merge({ "sha" => sha })
          )
        )
      end
    end
  end
