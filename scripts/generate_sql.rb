require "net/http"
require "uri"
require "json"
require "pg"
require "mini_sql"

API_KEY = ENV["OPENAI_API_KEY"]
RAW_DB = PG.connect(dbname: "discourse_development")
DB = MiniSql::Connection.get(RAW_DB)
EMBEDDINGS_DIR = File.join(__dir__, "../examples/embeddings")
EXAMPLES_DIR = File.join(__dir__, "../examples")

def get_schema
  schema = []
  table_name = nil
  columns = nil

  priority_tables = %w[posts topics notifications users user_actions]

  DB
    .query(<<~SQL, priority_tables)
        select table_name, column_name from information_schema.columns
        where table_schema = 'public'
        order by case when table_name in (?) then 0 else 1 end asc, table_name
      SQL
    .each do |row|
      if table_name != row.table_name
        schema << "#{table_name}(#{columns.join(",")})" if columns
        table_name = row.table_name
        columns = []
      end
      columns << row.column_name
    end

  schema << "#{table_name}(#{columns.join(",")})"

  schema
end

def get_messages(schema, question)
  messages = [
    {
      role: "system",
      content:
        "you are a bot that only speaks postgres SQL, you are asked questions and always reply in SQL, without explaining anything"
    },
    { role: "user", content: <<~TEXT },
        The user_actions tables stores likes (action_type 1).
        the topics table stores private/personal messages it uses archetype private_message for them.
        notification_level can be: {muted: 0, regular: 1, tracking: 2, watching: 3, watching_first_post: 4}.
      TEXT
    { role: "assistant", content: "SELECT 1 FROM acknowledged" },
    { role: "user", content: "am I happy?" },
    { role: "assistant", content: "SELECT 1 FROM i_dont_know" },
    { role: "user", content: "how many topics did sam create today?" },
    { role: "assistant", content: <<~SQL },
          SELECT COUNT(*)
          FROM topics
          WHERE user_id =
            (SELECT id from users where username = 'sam') AND
            created_at >= NOW() - INTERVAL '1 day'
        SQL
    { role: "user", content: "what categories is joe muting or watching?" },
    { role: "assistant", content: <<~SQL }
        SELECT category_id, notification_level
        FROM category_users cu
        JOIN users u ON u.id = cu.user_id
        WHERE cu.notification_level in (0, 3) AND
          u.username = 'joe'
       SQL
  ]

  # find_closest(question, count: 1).each do |name|
  #   question, sql = get_example(name)
  #   p question
  #   p sql
  #   messages << { role: "user", content: question }
  #   messages << { role: "assistant", content: sql }
  # end

  messages << {
    role: "system",
    content: "consider the DB has this schema:\n #{schema.join("\n")}"
  }

  messages << { role: "user", content: question }

  messages
end

def get_question
  puts "What query would you like to write?"
  gets.chomp
end

def send_request(messages)
  uri = URI("https://api.openai.com/v1/chat/completions")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request["Content-Type"] = "application/json"
  request["Authorization"] = "Bearer #{API_KEY}"
  request.body = { model: "gpt-3.5-turbo-16k", messages: messages }.to_json
  response = http.request(request)
  JSON.parse(response.body)
end

def get_embeddings(description)
  uri = URI.parse("https://api.openai.com/v1/embeddings")
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request["Authorization"] = "Bearer #{ENV["OPENAI_API_KEY"]}"

  request.body =
    JSON.dump({ "input" => description, "model" => "text-embedding-ada-002" })

  response =
    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https"
    ) { |http| http.request(request) }

  JSON.parse(response.body)["data"][0]["embedding"]
end

def find_closest(text, count: 3)
  DB.query("BEGIN")
  DB.query(
    "CREATE TEMP TABLE helper_embeddings (id serial primary key, name text, embeddings vector(1536))"
  )

  Dir
    .glob(File.join(EMBEDDINGS_DIR, "*.json"))
    .each do |file|
      json = JSON.parse(File.read(file))
      DB.exec(
        "INSERT INTO helper_embeddings (name, embeddings) VALUES (:name, '[:embeddings]')",
        name: File.basename(file, ".json"),
        embeddings: json["data"][0]["embedding"]
      )
    end

  names =
    DB.query_single(
      "SELECT name FROM helper_embeddings ORDER BY embeddings <-> '[:embeddings]' limit :limit",
      embeddings: get_embeddings(text),
      limit: count
    )
  DB.query("ROLLBACK")

  names
end

def get_example(name)
  File.read(File.join(EXAMPLES_DIR, "#{name}.txt")).split("\n", 2).map(&:strip)
end

def main
  question = get_question
  schema = get_schema
  messages = get_messages(schema, question)
  response_data = send_request(messages)

  #p response_data

  text = response_data.dig("choices", 0, "message", "content")

  if !text
    p response_data
    exit 1
  end

  puts text
end

main
