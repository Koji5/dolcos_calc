# 「Turbo Stream と Flash を統合した通知＆部分更新ヘルパ」の実装

（＝フレーム差し替えと同時にフラッシュを安全に“その場で一度だけ”表示する仕組み）

* **Turbo+Flash ヘルパ**（部分更新＋通知）
* **Flash-aware Turbo Stream ユーティリティ**
* **部分更新＆フラッシュ統合ヘルパ**（append/update対応）

要点：

* Turbo Streamで**フレーム差し替え**（template+assigns）
* 同時に**フラッシュDOMを更新**（通常遷移はサーバーレンダ、フレーム時はappend）
* 表示後は `discard` で**持ち越し防止**
* **プリフェッチ無害化**のガードとセットで運用

## 手順

1. `app\views\layouts\application.html.erb` <head> 内に

    ```erb
    <meta name="turbo-prefetch" content="false">
    ```

1. `app\controllers\application_controller.rb`  
    （`before_action :block_prefetch` の流れは保険。なくてもよい）

    ```ruby
    class ApplicationController < ActionController::Base
      before_action :block_prefetch
      allow_browser versions: :modern

      private

      # 「プリフェッチは無害応答」にする
      def prefetch_request?
        h = request.headers
        val = ->(k) { h[k].to_s.downcase }
        val["Purpose"] == "prefetch" ||
          val["Sec-Purpose"].include?("prefetch") ||
          val["X-Moz"] == "prefetch" ||
          val["X-Sec-Purpose"].include?("prefetch") ||
          val["Purpose"] == "prerender" ||
          val["Sec-Purpose"].include?("prerender") ||
          val["X-Sec-Purpose"].include?("prerender")
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
    ```

2. `app\helpers\application_helper.rb`

    Rails の flash を Bootstrap の見た目に寄せる

    ```ruby
    module ApplicationHelper
      def bootstrap_class_for(type)
        {
          notice:  "success",
          alert:   "danger",
          error:   "danger",
          warning: "warning",
          info:    "info"
        }[type.to_sym] || type.to_s
      end
      def flash_auto_dismiss?(type)
        %i[notice info].include?(type.to_sym)
      end
    end
    ```

3. `app\javascript\controllers\auto_dismiss_controller.js`

    Flash が自動で消える Stimulus コントローラー

    ```javascript
    import { Controller } from "@hotwired/stimulus"

    export default class extends Controller {
      static values = {
        delay: Number
      }

      connect() {
        document.scrollingElement?.scrollTo({ top: 0, behavior: "smooth" })
        if (this.hasDelayValue) {
          setTimeout(() => this._animateAndRemove(), this.delayValue)
        }
      }

      dismiss(event) {
        event.preventDefault()
        this._animateAndRemove()
      }

      _animateAndRemove() {
        const el = this.element
        const height = el.scrollHeight + "px"

        el.style.height = height
        el.offsetHeight // reflow で height を確定
        el.style.transition = "opacity 0.6s ease, height 0.6s ease, margin 0.6s ease, padding 0.6s ease"
        el.style.opacity = "0"
        el.style.height = "0"
        el.style.margin = "0"
        el.style.padding = "0"
        el.style.overflow = "hidden"

        setTimeout(() => {
          this.element.remove()
        }, 600)
      }
    }
    ```

4. `app\views\shared\_alert.html.erb`

    Flash本体。  
    `notice:`, `info:` は 5000msで自動的に消える設定。  
    時間を変えたい場合はこの数値を変える。
    ```erb
    <% flash.each do |type, messages| %>
      <% Array(messages).each do |message| %>
        <div class="alert alert-<%= bootstrap_class_for(type) %> alert-dismissible fade show my-0"
            role="alert"
            data-controller="auto-dismiss"
            <%= raw("data-auto-dismiss-delay-value=\"5000\"") if flash_auto_dismiss?(type) %>>
          <%= message %>
          <button type="button" class="btn-close" data-action="auto-dismiss#dismiss" aria-label="閉じる"></button>
        </div>
      <% end %>
    <% end %>
    ```
