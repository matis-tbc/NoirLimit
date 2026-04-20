import { useState } from "react";
import { parseEther } from "viem";
import { ActionCode } from "../utils/phase";

interface Props {
  enabled: boolean;
  isPending: boolean;
  onAct: (action: ActionCode, raise?: bigint) => void;
}

export function ActionBar({ enabled, isPending, onAct }: Props) {
  const [raise, setRaise] = useState("0.0002");

  const Btn = ({ label, onClick }: { label: string; onClick: () => void }) => (
    <button
      onClick={onClick}
      disabled={!enabled || isPending}
      className="px-4 py-2 border border-edge hover:border-gold disabled:opacity-30 transition uppercase tracking-widest text-sm"
    >
      {label}
    </button>
  );

  return (
    <div className="flex gap-2 items-center p-3 border border-edge rounded">
      <Btn label="Fold" onClick={() => onAct(ActionCode.FOLD)} />
      <Btn label="Check" onClick={() => onAct(ActionCode.CHECK)} />
      <Btn label="Call" onClick={() => onAct(ActionCode.CALL)} />
      <div className="flex items-center gap-2 ml-2">
        <input
          value={raise}
          onChange={(e) => setRaise(e.target.value)}
          className="bg-[#111] border border-edge px-2 py-1 w-24 text-sm"
        />
        <span className="text-xs">ETH</span>
        <Btn
          label="Raise"
          onClick={() => {
            try {
              onAct(ActionCode.RAISE, parseEther(raise));
            } catch {
              /* invalid */
            }
          }}
        />
      </div>
    </div>
  );
}
