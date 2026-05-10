import { SwapTerminal } from "./swap/SwapTerminal";
import { getApiModeLabel } from "./swap/api";

export function App() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <div className="brand">XMR / STRK</div>
          <div className="network">{getApiModeLabel()}</div>
        </div>
        <nav aria-label="Primary">
          <a href="#swap">Swap</a>
          <a href="#history" aria-disabled="true">History</a>
          <a href="#docs" aria-disabled="true">Docs</a>
        </nav>
      </header>

      <section id="swap" className="swap-stage" aria-label="Atomic swap">
        <SwapTerminal />
      </section>
    </main>
  );
}
