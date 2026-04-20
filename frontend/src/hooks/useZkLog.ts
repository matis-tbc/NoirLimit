import { useSyncExternalStore } from "react";
import { zkLog } from "../utils/zkLog";

export function useZkLog() {
  return useSyncExternalStore(zkLog.subscribe, zkLog.getSnapshot, zkLog.getSnapshot);
}
