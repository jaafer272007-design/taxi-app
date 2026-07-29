import { redirect } from "next/navigation";

// `proxy.ts` already gates every route behind the session cookie, so by the
// time this renders the visitor is authenticated.
export default function Home() {
  redirect("/dashboard");
}
