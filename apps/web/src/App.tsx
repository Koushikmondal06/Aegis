import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  ArrowDownToLine,
  ArrowUpRight,
  Check,
  ChevronRight,
  CircleAlert,
  Copy,
  Fingerprint,
  Gauge,
  KeyRound,
  LayoutDashboard,
  Link2,
  LockKeyhole,
  Menu,
  Network,
  Plus,
  RefreshCw,
  ShieldCheck,
  UsersRound,
  Wallet,
  X,
} from "lucide-react";
import {
  createPublicClient,
  createWalletClient,
  formatEther,
  getAddress,
  http,
  type Address,
} from "viem";
import { sepolia } from "viem/chains";

type Page =
  | "dashboard"
  | "create"
  | "account"
  | "send"
  | "batch"
  | "history"
  | "sponsorship"
  | "session-keys"
  | "guardians"
  | "settings";

type EthereumProvider = {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
};

declare global {
  interface Window {
    ethereum?: EthereumProvider;
  }
}

const navGroups = [
  {
    label: "Wallet",
    items: [
      ["dashboard", "Dashboard", LayoutDashboard],
      ["create", "Create account", Plus],
      ["account", "Account details", Wallet],
      ["send", "Send assets", ArrowUpRight],
      ["batch", "Batch transactions", Link2],
      ["history", "Activity", Activity],
    ],
  },
  {
    label: "Security",
    items: [
      ["sponsorship", "Gas sponsorship", Gauge],
      ["session-keys", "Session keys", KeyRound],
      ["guardians", "Guardians & recovery", UsersRound],
      ["settings", "Settings", Network],
    ],
  },
] as const;

const factoryAbi = [
  {
    name: "getAddress",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "salt", type: "uint256" },
    ],
    outputs: [{ name: "account", type: "address" }],
  },
] as const;

function shortAddress(value?: string) {
  return value ? `${value.slice(0, 6)}…${value.slice(-4)}` : "Not connected";
}

function copyText(value: string) {
  void navigator.clipboard?.writeText(value);
}

export function App() {
  const [page, setPage] = useState<Page>("dashboard");
  const [mobileOpen, setMobileOpen] = useState(false);
  const [owner, setOwner] = useState<Address>();
  const [smartAccount, setSmartAccount] = useState<Address>();
  const [balance, setBalance] = useState<bigint>();
  const [salt, setSalt] = useState("0");
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(false);

  const rpcUrl = import.meta.env.VITE_SEPOLIA_RPC_URL as string | undefined;
  const factoryAddress = import.meta.env.VITE_FACTORY_ADDRESS as Address | undefined;
  const publicClient = useMemo(
    () => createPublicClient({ chain: sepolia, transport: http(rpcUrl || undefined) }),
    [rpcUrl],
  );

  useEffect(() => {
    void restoreConnection();
  }, []);

  useEffect(() => {
    if (owner && factoryAddress) void refreshAccount(owner, BigInt(salt || "0"));
  }, [owner, factoryAddress, salt]);

  async function restoreConnection() {
    if (!window.ethereum) return;
    const accounts = (await window.ethereum.request({ method: "eth_accounts" })) as string[];
    if (accounts[0]) setOwner(getAddress(accounts[0]));
  }

  async function connectWallet() {
    setError(undefined);
    if (!window.ethereum) {
      setError("No injected wallet was found. Install a wallet extension to continue.");
      return;
    }
    setLoading(true);
    try {
      const accounts = (await window.ethereum.request({ method: "eth_requestAccounts" })) as string[];
      if (!accounts[0]) throw new Error("The wallet did not return an account.");
      setOwner(getAddress(accounts[0]));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Wallet connection failed.");
    } finally {
      setLoading(false);
    }
  }

  async function refreshAccount(accountOwner: Address, accountSalt: bigint) {
    if (!factoryAddress) return;
    try {
      const address = await publicClient.readContract({
        address: factoryAddress,
        abi: factoryAbi,
        functionName: "getAddress",
        args: [accountOwner, accountSalt],
      });
      setSmartAccount(address);
      setBalance(await publicClient.getBalance({ address }));
    } catch (cause) {
      setSmartAccount(undefined);
      setBalance(undefined);
      setError(cause instanceof Error ? cause.message : "Could not read the factory address.");
    }
  }

  const configured = Boolean(rpcUrl && factoryAddress && import.meta.env.VITE_ENTRY_POINT_ADDRESS);

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileOpen ? "sidebar-open" : ""}`}>
        <div className="brand-row">
          <div className="brand-mark"><ShieldCheck size={19} /></div>
          <div><strong>Aegis</strong><span>Wallet</span></div>
          <button className="icon-button mobile-close" onClick={() => setMobileOpen(false)}><X size={18} /></button>
        </div>
        <div className="security-pill"><span className="status-dot" /> ERC-4337 secured</div>
        <nav>
          {navGroups.map((group) => (
            <div className="nav-group" key={group.label}>
              <div className="nav-label">{group.label}</div>
              {group.items.map(([id, label, Icon]) => (
                <button
                  className={`nav-item ${page === id ? "active" : ""}`}
                  key={id}
                  onClick={() => { setPage(id); setMobileOpen(false); }}
                >
                  <Icon size={17} strokeWidth={1.8} />
                  <span>{label}</span>
                </button>
              ))}
            </div>
          ))}
        </nav>
        <div className="sidebar-footer">
          <div className="network-badge"><span className="network-dot" /> Sepolia testnet</div>
          <p>Testnet only · Never deposit production funds.</p>
        </div>
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <button className="icon-button mobile-menu" onClick={() => setMobileOpen(true)}><Menu size={20} /></button>
          <div className="breadcrumbs"><span>Aegis Wallet</span><ChevronRight size={14} /><strong>{pageTitle(page)}</strong></div>
          <div className="topbar-actions">
            <div className="chain-chip"><span className="network-dot" /> Sepolia</div>
            {owner ? (
              <button className="wallet-chip" onClick={() => copyText(owner)}><span className="wallet-avatar"><Fingerprint size={15} /></span>{shortAddress(owner)}<Copy size={13} /></button>
            ) : (
              <button className="primary-button compact" onClick={() => void connectWallet()} disabled={loading}>{loading ? "Connecting…" : "Connect wallet"}</button>
            )}
          </div>
        </header>

        <div className="content-wrap">
          {error && <div className="alert error-alert"><CircleAlert size={18} /><span>{error}</span><button onClick={() => setError(undefined)}><X size={15} /></button></div>}
          {!configured && <div className="alert setup-alert"><CircleAlert size={18} /><div><strong>Configuration required</strong><span>Set the Sepolia RPC, EntryPoint, and factory addresses in <code>apps/web/.env</code> to read live account state.</span></div></div>}
          {renderPage(page, { owner, smartAccount, balance, salt, setSalt, onConnect: connectWallet, onCopy: copyText, configured, onNavigate: setPage })}
        </div>
      </main>
    </div>
  );
}

function pageTitle(page: Page) {
  return {
    dashboard: "Dashboard", create: "Create smart account", account: "Account details", send: "Send assets",
    batch: "Batch transactions", history: "Transaction history", sponsorship: "Gas sponsorship",
    "session-keys": "Session keys", guardians: "Guardians & recovery", settings: "Settings",
  }[page];
}

type PageProps = {
  owner?: Address;
  smartAccount?: Address;
  balance?: bigint;
  salt: string;
  setSalt: (value: string) => void;
  onConnect: () => Promise<void>;
  onCopy: (value: string) => void;
  configured: boolean;
  onNavigate: (page: Page) => void;
};

function renderPage(page: Page, props: PageProps) {
  switch (page) {
    case "dashboard": return <Dashboard {...props} />;
    case "create": return <CreateAccount {...props} />;
    case "account": return <AccountDetails {...props} />;
    case "send": return <ActionPlaceholder icon={ArrowUpRight} title="Send assets" copy="Prepare an ERC-4337 UserOperation for ETH or ERC-20 transfers." {...props} />;
    case "batch": return <ActionPlaceholder icon={Link2} title="Batch transactions" copy="Compose an atomic executeBatch call with explicit per-call review." {...props} />;
    case "history": return <History {...props} />;
    case "sponsorship": return <SecurityPage icon={Gauge} title="Gas sponsorship" eyebrow="Policy-controlled" copy="Sponsorship is only available when the on-chain paymaster allowlist and signed policy approve the operation." />;
    case "session-keys": return <SecurityPage icon={KeyRound} title="Session keys" eyebrow="Least privilege" copy="Temporary keys are bound to expiry, target contracts, function selectors, and cumulative value limits." />;
    case "guardians": return <SecurityPage icon={UsersRound} title="Guardians & recovery" eyebrow="Delayed recovery" copy="Guardian recovery requires the configured threshold and delay. No frontend approval is treated as authorization." />;
    case "settings": return <Settings {...props} />;
  }
}

function Dashboard({ owner, smartAccount, balance, onNavigate, onConnect, configured }: PageProps) {
  return <>
    <section className="hero-row"><div><div className="eyebrow">SECURITY-FIRST ACCOUNT ABSTRACTION</div><h1>Your wallet, with guardrails.</h1><p className="lede">Aegis turns account abstraction into a calm, inspectable experience.</p></div><button className="secondary-button" onClick={() => onNavigate("account")}><LockKeyhole size={16} /> Review security</button></section>
    {!owner ? <EmptyState icon={Wallet} title="Connect an owner wallet" copy="Connect an EOA to derive a deterministic smart account address. Aegis never invents balances or transaction history." action="Connect wallet" onClick={() => void onConnect()} /> : !configured ? <EmptyState icon={Network} title="Finish network configuration" copy="The wallet is connected, but this local build has no contract addresses configured yet." action="Open settings" onClick={() => onNavigate("settings")} /> : <>
      <div className="account-banner"><div className="account-orb"><ShieldCheck size={24} /></div><div className="account-banner-copy"><span>Smart account</span><strong>{shortAddress(smartAccount)}</strong><small>{smartAccount ?? "Address unavailable"}</small></div><div className="banner-status"><span className="status-dot" /> Counterfactual ready</div><button className="icon-button" onClick={() => smartAccount && copyText(smartAccount)}><Copy size={16} /></button></div>
      <div className="metrics-grid"><Metric label="Native balance" value={balance === undefined ? "—" : `${formatEther(balance)} ETH`} sub="Sepolia testnet" icon={Wallet} /><Metric label="Account status" value="Not deployed" sub="Deploy on first UserOperation" icon={Fingerprint} /><Metric label="Gas policy" value="Configured" sub="Paymaster approval required" icon={Gauge} /><Metric label="Security score" value="Baseline" sub="Add guardians and session rules" icon={ShieldCheck} /></div>
      <div className="section-heading"><div><div className="eyebrow">QUICK ACTIONS</div><h2>Move with confidence</h2></div></div><div className="quick-grid"><QuickAction icon={ArrowUpRight} title="Send assets" copy="ETH and ERC-20" onClick={() => onNavigate("send")} /><QuickAction icon={Link2} title="Batch calls" copy="Atomic execution" onClick={() => onNavigate("batch")} /><QuickAction icon={KeyRound} title="Add session key" copy="Limit permissions" onClick={() => onNavigate("session-keys")} /><QuickAction icon={UsersRound} title="Configure guardians" copy="Recovery policy" onClick={() => onNavigate("guardians")} /></div>
    </>}
  </>;
}

function CreateAccount({ owner, smartAccount, salt, setSalt, onConnect, onCopy }: PageProps) {
  return <><PageIntro eyebrow="COUNTERFACTUAL DEPLOYMENT" title="Create a smart account" copy="Aegis derives the address before deployment. The account is deployed by EntryPoint's SenderCreator when the first UserOperation is included." /><div className="two-column"><div className="panel form-panel"><div className="field-label">Owner wallet</div><div className="readonly-field">{owner ? shortAddress(owner) : "Connect a wallet first"}</div><div className="field-label">Salt</div><input className="text-input" value={salt} onChange={(event) => setSalt(event.target.value.replace(/[^0-9]/g, ""))} inputMode="numeric" /><div className="review-row"><span>Deterministic address</span><span className="mono">{smartAccount ? shortAddress(smartAccount) : "—"}</span></div><button className="primary-button full" disabled={!owner || !smartAccount}>Deploy through UserOperation <ArrowUpRight size={16} /></button><p className="form-note"><CircleAlert size={14} /> Deployment requires a configured bundler and funded account or eligible paymaster.</p></div><SecurityChecklist /></div><div className="panel address-panel"><div className="panel-heading"><div><div className="eyebrow">ADDRESS PREVIEW</div><h3>Safe to receive</h3></div><Fingerprint size={22} className="accent-icon" /></div><p>Funds can be sent to the predicted address before deployment. Verify the network and address before transferring assets.</p><div className="address-box">{smartAccount ?? "Connect wallet and configure the factory"}{smartAccount && <button className="icon-button" onClick={() => onCopy(smartAccount)}><Copy size={15} /></button>}</div></div></>;
}

function AccountDetails({ owner, smartAccount, balance, onCopy }: PageProps) {
  return <><PageIntro eyebrow="ACCOUNT DETAILS" title="Inspect your security boundary" copy="The account owns assets, but only the configured EntryPoint can reach its execution methods." /><div className="two-column"><div className="panel"><div className="panel-heading"><div><div className="eyebrow">IDENTITY</div><h3>Smart account</h3></div><ShieldCheck className="accent-icon" size={22} /></div><DetailRow label="Address" value={smartAccount ?? "Not derived"} copy={smartAccount ? () => onCopy(smartAccount) : undefined} /><DetailRow label="Owner" value={owner ?? "Not connected"} copy={owner ? () => onCopy(owner) : undefined} /><DetailRow label="Balance" value={balance === undefined ? "—" : `${formatEther(balance)} ETH`} /><DetailRow label="Network" value="Ethereum Sepolia" /></div><div className="panel"><div className="panel-heading"><div><div className="eyebrow">CONTROLS</div><h3>Authorization layers</h3></div><LockKeyhole className="accent-icon" size={22} /></div><SecurityRow label="Owner signatures" value="Enabled" tone="good" /><SecurityRow label="EntryPoint gate" value="Pinned v0.8" tone="good" /><SecurityRow label="Session keys" value="Not configured" tone="muted" /><SecurityRow label="Guardian recovery" value="Not configured" tone="muted" /></div></div></>;
}

function History(_props: PageProps) { return <><PageIntro eyebrow="READ MODEL" title="Transaction history" copy="Included UserOperations will appear here after the indexer is configured. Aegis never treats an indexer as the source of truth." /><EmptyState icon={Activity} title="No indexed activity yet" copy="This workspace has no transaction indexer or deployed account configured. Connect a bundler and indexer to populate this view." action="Configure settings" /></>; }

function ActionPlaceholder({ icon: Icon, title, copy, onNavigate }: PageProps & { icon: typeof ArrowUpRight; title: string; copy: string }) { return <><PageIntro eyebrow="USEROPERATION BUILDER" title={title} copy={copy} /><div className="panel empty-panel"><div className="large-icon"><Icon size={26} /></div><h3>Ready for real infrastructure</h3><p>Connect a compatible EntryPoint v0.8 bundler in Settings. This screen will never show a successful operation until a UserOperation receipt and transaction receipt are confirmed.</p><button className="secondary-button" onClick={() => onNavigate("settings")}>Open network settings <ChevronRight size={16} /></button></div></>; }

function SecurityPage({ icon: Icon, title, eyebrow, copy }: { icon: typeof Gauge; title: string; eyebrow: string; copy: string }) { return <><PageIntro eyebrow={eyebrow} title={title} copy={copy} /><div className="three-column"><InfoCard icon={Icon} title="On-chain enforcement" copy="The contract, not this interface, decides whether an operation is valid." /><InfoCard icon={ShieldCheck} title="Explicit failure states" copy="Expired, revoked, disallowed, or underfunded requests remain visible and actionable." /><InfoCard icon={LockKeyhole} title="Review before signing" copy="Aegis separates preparation, signature, submission, and inclusion." /></div><div className="panel empty-panel compact-empty"><div className="eyebrow">IMPLEMENTATION STATUS</div><h3>Policy module is present; network wiring is next.</h3><p>Use the contract tests and documentation in this repository to configure the corresponding on-chain policy before enabling this workflow for users.</p></div></>; }

function Settings({ configured }: PageProps) { return <><PageIntro eyebrow="CONFIGURATION" title="Network settings" copy="Keep RPC, bundler, EntryPoint, and factory configuration explicit. Secrets never belong in the frontend bundle." /><div className="panel settings-panel"><Setting label="Network" value="Ethereum Sepolia (11155111)" /><Setting label="RPC endpoint" value={import.meta.env.VITE_SEPOLIA_RPC_URL ? "Configured" : "Missing"} tone={import.meta.env.VITE_SEPOLIA_RPC_URL ? "good" : "warn"} /><Setting label="EntryPoint v0.8" value={import.meta.env.VITE_ENTRY_POINT_ADDRESS ? shortAddress(import.meta.env.VITE_ENTRY_POINT_ADDRESS) : "Missing"} tone={import.meta.env.VITE_ENTRY_POINT_ADDRESS ? "good" : "warn"} /><Setting label="Factory" value={import.meta.env.VITE_FACTORY_ADDRESS ? shortAddress(import.meta.env.VITE_FACTORY_ADDRESS) : "Missing"} tone={import.meta.env.VITE_FACTORY_ADDRESS ? "good" : "warn"} /><Setting label="Bundler" value={import.meta.env.VITE_SEPOLIA_BUNDLER_RPC_URL ? "Configured" : "Optional until submit"} tone={import.meta.env.VITE_SEPOLIA_BUNDLER_RPC_URL ? "good" : "muted"} /><div className="settings-note"><CircleAlert size={16} /><span>{configured ? "Read-only chain configuration is available." : "Copy apps/web/.env.example to apps/web/.env and provide the deployed addresses."}</span></div></div></>; }

function PageIntro({ eyebrow, title, copy }: { eyebrow: string; title: string; copy: string }) { return <section className="page-intro"><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p className="lede">{copy}</p></section>; }
function EmptyState({ icon: Icon, title, copy, action, onClick }: { icon: typeof Wallet; title: string; copy: string; action: string; onClick?: () => void }) { return <div className="panel empty-panel"><div className="large-icon"><Icon size={26} /></div><h3>{title}</h3><p>{copy}</p><button className="primary-button" onClick={onClick} disabled={!onClick}>{action} <ChevronRight size={16} /></button></div>; }
function Metric({ label, value, sub, icon: Icon }: { label: string; value: string; sub: string; icon: typeof Wallet }) { return <div className="metric-card"><div className="metric-icon"><Icon size={17} /></div><span>{label}</span><strong>{value}</strong><small>{sub}</small></div>; }
function QuickAction({ icon: Icon, title, copy, onClick }: { icon: typeof ArrowUpRight; title: string; copy: string; onClick: () => void }) { return <button className="quick-action" onClick={onClick}><span className="quick-icon"><Icon size={18} /></span><span><strong>{title}</strong><small>{copy}</small></span><ChevronRight size={16} /></button>; }
function InfoCard({ icon: Icon, title, copy }: { icon: typeof Gauge; title: string; copy: string }) { return <div className="panel info-card"><div className="large-icon"><Icon size={22} /></div><h3>{title}</h3><p>{copy}</p></div>; }
function SecurityChecklist() { return <div className="panel checklist"><div className="panel-heading"><div><div className="eyebrow">DEPLOYMENT CHECKLIST</div><h3>Before you sign</h3></div><ShieldCheck className="accent-icon" size={22} /></div>{["Verify Sepolia network", "Review EntryPoint address", "Confirm factory prediction", "Fund account or choose sponsorship"].map((item) => <div className="check-row" key={item}><span className="check"><Check size={13} /></span><span>{item}</span></div>)}</div>; }
function DetailRow({ label, value, copy }: { label: string; value: string; copy?: () => void }) { return <div className="detail-row"><span>{label}</span><strong className={value.startsWith("0x") ? "mono" : ""}>{value}</strong>{copy && <button className="icon-button" onClick={copy}><Copy size={14} /></button>}</div>; }
function SecurityRow({ label, value, tone }: { label: string; value: string; tone: "good" | "muted" }) { return <div className="security-row"><span>{label}</span><strong className={`tone-${tone}`}><span className="status-dot" />{value}</strong></div>; }
function Setting({ label, value, tone = "muted" }: { label: string; value: string; tone?: "good" | "warn" | "muted" }) { return <div className="setting-row"><span>{label}</span><strong className={`tone-${tone}`}>{value}</strong></div>; }
