import { useEffect, useState } from "react";

interface Props {
  pending: boolean;
}

// Fixed banner that appears when the app is waiting on the user's wallet
// (MetaMask popup). Because MetaMask often opens in a separate notification
// window rather than inline, users otherwise have no clue where the popup
// went. This banner stays visible until the signature request resolves so
// the expected action is always obvious.
export function WalletPendingBanner({ pending }: Props) {
  // Delay appearance by 150ms so instant confirms don't flash the banner.
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    if (!pending) {
      setVisible(false);
      return;
    }
    const id = setTimeout(() => setVisible(true), 150);
    return () => clearTimeout(id);
  }, [pending]);

  if (!visible) return null;

  return (
    <div
      className="fixed top-4 left-1/2 -translate-x-1/2 z-50 border border-gold/60 bg-bg/95 backdrop-blur px-4 py-2 rounded shadow-lg flex items-center gap-3"
      role="status"
      aria-live="polite"
    >
      <span className="w-2 h-2 rounded-full bg-gold animate-pulse shrink-0" />
      <div className="text-sm">
        <div className="text-gold uppercase tracking-widest text-[10px]">
          Waiting for wallet signature
        </div>
        <div className="text-ink/70 text-[11px]">
          Check your MetaMask popup. If you don't see it, click the MetaMask
          extension icon in your toolbar.
        </div>
      </div>
    </div>
  );
}
