import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  allowedSupportMimeTypes,
  extensionForMime,
  maxSupportAttachmentBytes,
  validImageSignature,
} from "./logic.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const body = await req.json();
    let attachment: { bytes: Uint8Array; mime: string } | null = null;
    if (body.attachment_base64 != null) {
      const mime = String(body.attachment_mime ?? "");
      if (!allowedSupportMimeTypes.includes(mime)) {
        throw new Error("invalid_attachment");
      }
      const bytes = Uint8Array.from(
        atob(String(body.attachment_base64)),
        (c) => c.charCodeAt(0),
      );
      if (
        bytes.length === 0 || bytes.length > maxSupportAttachmentBytes ||
        !validImageSignature(bytes, mime)
      ) throw new Error("invalid_attachment");
      attachment = { bytes, mime };
    }
    const url = Deno.env.get("SUPABASE_URL")!;
    const authHeader = req.headers.get("Authorization") ??
      `Bearer ${Deno.env.get("SUPABASE_ANON_KEY")!}`;
    const client = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    if (body.action === "signed_url") {
      const path = String(body.path ?? "");
      const { data: allowed, error: authorizationError } = await client.rpc(
        "authorize_platform_owner_support_attachment",
        { p_path: path },
      );
      if (authorizationError || allowed !== true) {
        throw new Error("Unauthorized");
      }
      const { data, error: signedUrlError } = await admin.storage
        .from("support-attachments").createSignedUrl(path, 300);
      if (signedUrlError) throw signedUrlError;
      return new Response(
        JSON.stringify({ ok: true, signed_url: data.signedUrl }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const { data: id, error } = await client.rpc(
      "submit_public_support_request",
      {
        p_full_name: body.full_name,
        p_email: body.email,
        p_gym_name: body.gym_name,
        p_issue_type: body.issue_type,
        p_screen_name: body.screen_name,
        p_description: body.description,
        p_app_version: body.app_version,
        p_build_number: body.build_number,
        p_platform: body.platform,
        p_os_version: body.os_version,
        p_locale: body.locale,
      },
    );
    if (error || !id) throw error ?? new Error("Request could not be created");
    if (attachment != null) {
      const path = `${id}/${crypto.randomUUID()}.${
        extensionForMime(attachment.mime)
      }`;
      const { error: uploadError } = await admin.storage.from(
        "support-attachments",
      ).upload(path, attachment.bytes, {
        contentType: attachment.mime,
        upsert: false,
      });
      if (uploadError) {
        await admin.from("public_support_requests").delete().eq("id", id);
        throw uploadError;
      }
      const { error: updateError } = await admin.from("public_support_requests")
        .update({ attachment_path: path }).eq("id", id);
      if (updateError) {
        await admin.storage.from("support-attachments").remove([path]);
        await admin.from("public_support_requests").delete().eq("id", id);
        throw updateError;
      }
    }
    return new Response(JSON.stringify({ ok: true, id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (_) {
    return new Response(
      JSON.stringify({ ok: false, error: "request_failed" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
