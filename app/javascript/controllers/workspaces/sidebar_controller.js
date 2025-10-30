import { Controller } from "@hotwired/stimulus"
import { Offcanvas } from "bootstrap"

/*
  サイドバー内のリンクをクリックしたら即座にオフキャンバスを閉じる。
  - XL未満（offcanvas動作中）のみ動く
  - data-turbo-frame が指定されたリンク（既定: main）のときに閉じる
  - 既存の遷移は止めない（preventDefaultしない）
*/
export default class extends Controller {
  static values = {
    frame: { type: String, default: "main" },      // 対象の Turbo Frame
    target: { type: String, default: "#appSidebar"} // Offcanvas 要素
  }

  connect() {
    this.onClick = this.onClick.bind(this)
    // サイドバー全体でデリゲート
    this.element.addEventListener("click", this.onClick, true) // captureにして先に拾う
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick, true)
  }

  onClick(e) {
    // クリックされた a[href] を特定
    const a = e.target.closest("a[href]")
    if (!a || !this.element.contains(a)) return

    // XL以上は静的サイドバーなので何もしない
    if (!window.matchMedia("(max-width: 1199.98px)").matches) return

    // data-turbo-frame の判定（既定は this.frameValue）
    const tf = (a.getAttribute("data-turbo-frame") || "").trim()
    const willUpdateTargetFrame =
      tf ? (tf === this.frameValue) : false

    // 「main を更新するリンク」のみ閉じる（必要なら true にすれば全リンクで閉じる）
    if (!willUpdateTargetFrame) return

    // オフキャンバスを閉じる（表示時のみ）
    const el = document.querySelector(this.targetValue)
    if (!el) return
    const api = Offcanvas.getInstance(el) || new Offcanvas(el)
    if (el.classList.contains("show")) api.hide()
  }
}
