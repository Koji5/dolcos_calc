class ApplicationController < ActionController::Base
  before_action :block_prefetch
  allow_browser versions: :modern

  # ユーザー切替時の処理
  def after_sign_out_path_for(_resource_or_scope)
    case params[:redirect]
    when "sign_in" then new_user_session_path
    when "sign_up" then new_user_registration_path
    else                unauthenticated_root_path
    end
  end

  private

  # 「プリフェッチは無害応答」にする
  def prefetch_request?
    h = request.headers
    h['Purpose'] == 'prefetch' ||
      h['Sec-Purpose'].to_s.include?('prefetch') ||
      h['X-Moz'] == 'prefetch' ||
      h['X-Sec-Purpose'].to_s.include?('prefetch')
  end

  def block_prefetch
    return unless prefetch_request?
    # Turbo Frame のプリフェッチだけ止めたいなら、以下の追加条件もOK
    # return unless request.headers['Turbo-Frame'].present? || request.format.turbo_stream?
    head :no_content
  end

  def render_flash_and_replace(
    target_id: "main",              # ← 置換する Turbo Frame/要素ID
    template:,                      # ← 必須: 描画するテンプレート "addresses/index" など
    assigns: {},                    # ← テンプレ用の @変数セット
    message: nil, type: nil,        # ← ローカル用フラッシュを、Railsのフラッシュと同時表示したいときだけ指定
    flash: nil                      # ← 明示上書きしたいとき以外は不要
  )
    f = flash || self.flash
    if message.present? && type.present?
      f[type] = Array(f[type]) << message
    end

    # フラッシュ HTML（ローカル箱 #alert を更新）
    alert_html = render_to_string(
      partial: "shared/alert",
      locals:  { flash: f },
      layout:  false
    )

    # 本体 HTML（template + assigns 専用）
    body_html = render_to_string(
      template: template,
      assigns:  assigns.merge(current_view: template),
      layout:   false
    )

    streams = []
    streams << turbo_stream.append("alert", alert_html) unless alert_html.strip.empty?
    streams << turbo_stream.update(target_id, body_html)

    f.discard if f.respond_to?(:discard) # 次に持ち越さない
    render turbo_stream: streams
  end

end
