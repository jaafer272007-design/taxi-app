"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Search } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

/**
 * One box, three kinds of answer.
 *
 * Support starts with whatever the caller can read out — a phone number, or an
 * id pasted from a screenshot. Making the admin pick the right field first is
 * a step that exists only because the software could not be bothered to look
 * in both places.
 *
 * The query goes into the URL rather than component state so a support case
 * can be linked to a colleague and survives a reload.
 */
export function SearchBox({ initial }: { initial: string }) {
  const [value, setValue] = useState(initial);
  const router = useRouter();

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const q = value.trim();
    router.push(q ? `/support?q=${encodeURIComponent(q)}` : "/support");
  };

  return (
    <form onSubmit={submit} className="flex gap-2">
      <Input
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="07XX XXX XXXX أو معرّف رحلة/حجز"
        aria-label="بحث"
        // Western digits and LTR: a phone number and a cuid are both
        // identifiers to be matched, not quantities to be read.
        dir="ltr"
        className="text-start"
      />
      <Button type="submit">
        <Search className="size-4" />
        بحث
      </Button>
    </form>
  );
}
