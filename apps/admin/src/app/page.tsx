import { redirect } from "next/navigation";

// `proxy.ts` already gates every route behind the session cookie, so by the
// time this renders the visitor is authenticated — just send them to the one
// section that exists today.
export default function Home() {
  redirect("/corridors");
}
