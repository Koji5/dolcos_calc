class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :trackable

  GUEST_EMAIL_PREFIX = "guest+".freeze
  GUEST_EMAIL_DOMAIN = "example.com".freeze

  def self.guest
    10.times do
      token     = SecureRandom.hex(4)               # 8桁（衝突しにくい）
      email     = "#{GUEST_EMAIL_PREFIX}#{token}@#{GUEST_EMAIL_DOMAIN}"
      password  = SecureRandom.urlsafe_base64(16)   # Deviseの最小長(デフォ6)を超える十分な長さ

      user = new(email: email, password: password, password_confirmation: password)

      # Confirmable を使っている場合はメール確認をスキップ
      user.skip_confirmation! if user.respond_to?(:skip_confirmation!)

      begin
        user.save!
        return user
      rescue ActiveRecord::RecordNotUnique
        # 非常にまれに email が衝突したらリトライ
        next
      end
    end
    raise "Failed to create guest user (email collision)"
  end

  def guest?
    email&.start_with?("guest+")
  end

  def admin?
    AdminConfig.admin?(email)
  end
end
