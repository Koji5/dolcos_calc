module AdminConfig
  module_function

  def admin_emails
    raw = ENV.fetch("ADMIN_MAIL_ADDRESS_LIST", "")
    raw.split(",").map { _1.strip.downcase }.reject(&:empty?).uniq
  end

  def admin?(email)
    return false if email.blank?
    admin_emails.include?(email.strip.downcase)
  end
end
