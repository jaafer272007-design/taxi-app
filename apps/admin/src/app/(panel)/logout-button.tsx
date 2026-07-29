import { LogOut } from "lucide-react";

import { Button } from "@/components/ui/button";
import { logoutAction } from "./actions";

export function LogoutButton() {
  return (
    <form action={logoutAction}>
      <Button
        type="submit"
        variant="ghost"
        size="sm"
        className="w-full justify-start gap-2 text-muted-foreground"
      >
        <LogOut className="size-4" />
        تسجيل الخروج
      </Button>
    </form>
  );
}
