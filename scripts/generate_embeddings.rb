require 'net/http'
require 'json'
require 'uri'

# Define the API endpoint
uri = URI.parse("https://api.openai.com/v1/embeddings")

# Define the request
request = Net::HTTP::Post.new(uri)
request.content_type = "application/json"
request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
Dir.glob('examples/*.txt').each do |file|
  description = File.open(file, &:readline).strip
  request.body = JSON.dump({
    "input" => description,
    "model" => "text-embedding-ada-002"
  })

  # Send the request
  response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    http.request(request)
  end

  # Generate SHA256 hash of the description
  sha = Digest::SHA256.hexdigest(description)
  
  # Check if a file with the same SHA256 hash already exists
  if File.exist?("embeddings/#{sha}.json")
    puts "Embedding for #{file} already exists. Skipping..."
  else
    puts "Generating embedding for #{file}..."
    
    # Send the request
    response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      http.request(request)
    end

    # Save the response to a JSON file
    File.open("embeddings/#{File.basename(file, '.txt')}.json", 'w') do |f|
      f.write(JSON.pretty_generate(JSON.parse(response.body).merge({"sha" => sha})))
    end
  end
end
