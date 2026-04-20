import { useAccount, useBalance, useSendTransaction, useChainId } from "wagmi";
import type { Address } from "viem";
import { formatEther, parseEther } from "viem";
import { sepolia } from "viem/chains";
import { makeBotClients } from "../bot/botWallet";

interface Props {
  botAddress?: Address;
}

const FUND_AMOUNT = parseEther("0.005");
const MIN_RUN = parseEther("0.004");
const MAX_HOLD = parseEther("0.05"); // sanity cap

export function FundBotPanel({ botAddress }: Props) {
  const { address } = useAccount();
  const chainId = useChainId();
  const { sendTransactionAsync, isPending } = useSendTransaction();
  const { data: bal, refetch } = useBalance({
    address: botAddress,
    query: { enabled: !!botAddress, refetchInterval: 6000 },
  });

  if (!botAddress || !address) return null;

  const onWrongChain = chainId !== sepolia.id;
  const ready = bal && bal.value >= MIN_RUN;
  const overFunded = bal && bal.value >= MAX_HOLD;

  const fund = async () => {
    if (onWrongChain) return;
    await sendTransactionAsync({ to: botAddress, value: FUND_AMOUNT });
    setTimeout(() => refetch(), 2000);
  };

  const sweep = async () => {
    if (!address) return;
    const bot = makeBotClients(address);
    const balance = await bot.publicClient.getBalance({ address: botAddress });
    if (balance === 0n) return;
    // Reserve enough for the sweep tx itself.
    const gasPrice = await bot.publicClient.getGasPrice();
    const reserve = gasPrice * 21000n * 2n;
    if (balance <= reserve) return;
    const value = balance - reserve;
    const hash = await bot.wallet.sendTransaction({
      to: address,
      value,
      account: bot.account,
      chain: bot.wallet.chain,
    } as any);
    await bot.publicClient.waitForTransactionReceipt({ hash });
    refetch();
  };

  return (
    <div className="border border-edge rounded p-4 space-y-2">
      <div className="text-xs uppercase tracking-widest text-ink/60">Bot wallet</div>
      <div className="text-sm break-all">{botAddress}</div>
      <div className="text-sm text-gold">
        Balance: {bal ? formatEther(bal.value) : "..."} ETH{" "}
        {ready ? (
          <span className="text-green-400">(ready)</span>
        ) : (
          <span className="text-red-400">(needs {formatEther(MIN_RUN)})</span>
        )}
      </div>
      {onWrongChain && (
        <div className="text-xs text-red-400">
          Wrong chain. Switch wallet to Sepolia before funding.
        </div>
      )}
      {overFunded && (
        <div className="text-xs text-yellow-400">
          Bot already holds {formatEther(MAX_HOLD)}+ ETH. Skip funding or sweep first.
        </div>
      )}
      <div className="flex gap-2 flex-wrap">
        <button
          disabled={isPending || onWrongChain || ready || overFunded}
          onClick={fund}
          className="px-3 py-1 border border-gold text-gold uppercase text-xs tracking-widest hover:bg-gold hover:text-bg disabled:opacity-30"
        >
          Fund {formatEther(FUND_AMOUNT)} ETH
        </button>
        <button
          disabled={isPending || !bal || bal.value === 0n}
          onClick={sweep}
          className="px-3 py-1 border border-edge text-xs uppercase tracking-widest disabled:opacity-30"
        >
          Sweep to host
        </button>
        <button
          disabled={isPending}
          onClick={() => refetch()}
          className="px-3 py-1 border border-edge text-xs uppercase tracking-widest"
        >
          Refresh
        </button>
      </div>
    </div>
  );
}
