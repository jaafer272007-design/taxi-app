import { Skeleton } from "@/components/ui/skeleton";

export default function CorridorsLoading() {
  return (
    <div className="grid gap-6">
      <div className="flex items-center justify-between">
        <div className="grid gap-2">
          <Skeleton className="h-6 w-40" />
          <Skeleton className="h-4 w-64" />
        </div>
        <Skeleton className="h-10 w-40" />
      </div>
      <div className="grid gap-2 rounded-xl border border-border p-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-12 w-full" />
        ))}
      </div>
    </div>
  );
}
