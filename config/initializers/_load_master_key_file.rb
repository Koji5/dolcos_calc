file = ENV["RAILS_MASTER_KEY_FILE"]
if ENV["RAILS_MASTER_KEY"].to_s.empty? && file && File.exist?(file)
  ENV["RAILS_MASTER_KEY"] = File.read(file).strip
end
