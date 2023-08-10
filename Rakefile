require 'rake'

namespace :ada do
  desc 'Generate ADA embeddings for all SQL files in the examples directory'
  task :generate_embeddings do
    Dir.glob('examples/*.sql').each do |file|
      system("python generate_embeddings.py #{file} embeddings")
    end
  end
end
