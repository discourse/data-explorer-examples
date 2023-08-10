require "openai"
require "pg"
require "mini_sql"

API_KEY = ENV["OPEN_AI_API_KEY"]

pg_conn = PG.connect(dbname: "discourse_development")
conn = MiniSql::Connection.get(pg_conn)

schema = []

table_name = nil
columns = nil

priority_tables = %w[posts topics notifications users user_actions]

conn
  .query(
    "select table_name, column_name from information_schema.columns order by case when table_name in (?) then 0 else 1 end asc, table_name ",
    priority_tables
  )
  .each do |row|
    if table_name != row.table_name
      schema << "#{table_name}(#{columns.join(",")})" if columns
      table_name = row.table_name
      columns = []
    end
    columns << row.column_name
  end

schema << "#{table_name}(#{columns.join(",")})"

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

puts "What query would you like to write?"
question = gets.chomp

chunked = []
chunk = +""
schema.each do |table|
  chunk << table
  chunk << " "
  if chunk.length > 4000
    chunked << chunk
    chunk = +""
  end
end
chunked << chunk if chunk.length > 0

chunked[0..2].each do |data|
  messages << { role: "user", content: "db schema: " + data }
end

messages << { role: "user", content: question }

client = OpenAI::Client.new(access_token: API_KEY)
response =
  client.chat(parameters: { model: "gpt-3.5-turbo", messages: messages })

text = response.dig("choices", 0, "message", "content")

#p response

if !text
  p response
  exit 1
end

# puts text

#puts
puts text
