const features = [
  ["Pencil-native", "Circle, point, or strike through the part you want to change."],
  ["Context-aware", "TouchCode connects what you see to the React source behind it."],
  ["Safe by default", "Review the live result before keeping a change in your project."],
] as const;

export default function App() {
  return (
    <main>
      <nav className="nav">
        <a className="brand" href="#top">TouchCode</a>
        <div className="navLinks">
          <a href="#features">Features</a>
          <a href="#workflow">Workflow</a>
        </div>
        <button className="secondaryButton">Join beta</button>
      </nav>

      <section className="hero" id="top">
        <p className="eyebrow">Build on Mac. Direct on iPad.</p>
        <h1>Point at your interface.<br />Tell your coding agent what to change.</h1>
        <p className="lede">
          TouchCode turns Apple Pencil annotations into precise React source context.
        </p>
        <div className="actions">
          <button className="primaryButton">Start creating</button>
          <button className="textButton">Watch the workflow →</button>
        </div>
      </section>

      <section className="previewCard" aria-label="TouchCode workflow preview">
        <div className="previewHeader">
          <span className="traffic red" />
          <span className="traffic yellow" />
          <span className="traffic green" />
          <span className="address">localhost:5173</span>
        </div>
        <div className="previewBody">
          <div className="annotationRing" />
          <button className="demoButton">Make this better</button>
          <p>Circle the button with Apple Pencil, then describe the change.</p>
        </div>
      </section>

      <section className="features" id="features">
        {features.map(([title, description]) => (
          <article key={title}>
            <h2>{title}</h2>
            <p>{description}</p>
          </article>
        ))}
      </section>
    </main>
  );
}

