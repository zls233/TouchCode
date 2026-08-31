export default function App() {
  return (
    <main>
      <nav className="nav">
        <a className="brand" href="#top">TouchCode Demo</a>
        <div className="navLinks">
          <a href="#products">Products</a>
          <a href="#pricing">Pricing</a>
        </div>
        <button className="secondaryButton">Join beta</button>
      </nav>

      <section className="hero" id="top">
        <p className="eyebrow">示例网页 · 可用 Pencil 圈选</p>
        <h1>圈住你想改的地方<br />告诉 AI 怎么改</h1>
        <p className="lede">试试：圈住下方按钮/卡片/标题，然后语音或文字下指令。</p>
        <div className="actions">
          <button className="primaryButton">Start creating</button>
          <button className="textButton">Watch workflow →</button>
        </div>
      </section>

      {/* 可圈选的卡片区 */}
      <section className="features" id="products" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(240px,1fr))", gap: 16 }}>
        {[
          { title: "Aurora Headphones", price: "¥899", desc: "主动降噪，40h 续航", color: "#eef4ff" },
          { title: "Nimbus Keyboard", price: "¥599", desc: "矮轴机械，手感轻盈", color: "#fff7ed" },
          { title: "Orbit Mouse", price: "¥299", desc: "8K 轮询，羽量 49g", color: "#f0fdf4" },
        ].map((p) => (
          <article key={p.title} style={{ background: p.color, borderRadius: 16, padding: 20, border: "1px solid #e5e7eb" }}>
            <div style={{ height: 120, borderRadius: 12, background: "#fff", display: "grid", placeItems: "center", fontSize: 32 }}>📦</div>
            <h2 style={{ margin: "12px 0 4px" }}>{p.title}</h2>
            <p style={{ color: "#6b7280", margin: 0 }}>{p.desc}</p>
            <p style={{ fontWeight: 700, margin: "8px 0" }}>{p.price}</p>
            <button className="primaryButton" style={{ width: "100%" }}>Buy now</button>
          </article>
        ))}
      </section>

      <section id="pricing" style={{ marginTop: 32, padding: 24, border: "1px dashed #cbd5e1", borderRadius: 16 }}>
        <h2>定价区（可圈改）</h2>
        <p>圈住此段说“改成三列卡片”“按钮变绿色”“标题更大”等，Bridge 会把截图+指令发给 Codex。</p>
        <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
          <span style={{ padding: "8px 14px", background: "#111827", color: "#fff", borderRadius: 999 }}>Pro ¥99/月</span>
          <span style={{ padding: "8px 14px", background: "#e5e7eb", borderRadius: 999 }}>Free ¥0</span>
        </div>
      </section>

      <p style={{ textAlign: "center", color: "#9ca3af", marginTop: 32 }}>提示：iPad 端双指长按唤醒语音，单指 Pencil 圈选。</p>
    </main>
  );
}
