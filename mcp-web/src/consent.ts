import {
  createClient,
  type AuthError,
  type OAuthAuthorizationDetails,
  type OAuthRedirect,
  type Session,
  type SupabaseClient,
} from "@supabase/supabase-js";

interface NextbodyConfig {
  supabaseUrl: string;
  supabaseKey: string;
  providers?: string[];
}

declare global {
  interface Window {
    NEXTBODY_CONFIG?: NextbodyConfig;
  }
}

interface ConsentCopy {
  title: string;
  kicker: string;
  missingId: string;
  notConfigured: string;
  signInTitle: string;
  signInLede: string;
  emailLabel: string;
  emailPlaceholder: string;
  sendCode: string;
  codeLabel: string;
  codePlaceholder: string;
  verify: string;
  differentEmail: string;
  apple: string;
  google: string;
  or: string;
  noAccount: string;
  codeSent: string;
  consentTitle: string;
  signedIn: string;
  notYou: string;
  readsTitle: string;
  reads: string[];
  write: string;
  notice: string;
  allow: string;
  deny: string;
  clientFallback: string;
  genericError: string;
  invalidEmail: string;
  invalidCode: string;
}

const en: ConsentCopy = {
  title: "Allow access",
  kicker: "NextBody",
  missingId: "This link is missing an authorization id. Start again from your assistant.",
  notConfigured: "This page is not configured.",
  signInTitle: "Sign in to NextBody",
  signInLede: "Use the same account as the NextBody app.",
  emailLabel: "Email",
  emailPlaceholder: "you@example.com",
  sendCode: "Email me a code",
  codeLabel: "6-digit code",
  codePlaceholder: "000000",
  verify: "Continue",
  differentEmail: "Use a different email",
  apple: "Continue with Apple",
  google: "Continue with Google",
  or: "or",
  noAccount: "No NextBody account for this email. Create one in the app first.",
  codeSent: "Enter the code we sent to",
  consentTitle: "Allow this assistant",
  signedIn: "Signed in as",
  notYou: "Not you? Sign out",
  readsTitle: "It will be able to read",
  reads: [
    "Sleep",
    "Heart and HRV",
    "Stress, steps, skin temperature and food-response points",
    "Body battery",
    "Training load",
    "Calories and meals",
    "Weight and body composition",
    "Workout records, balance checks and health profile (height, birth date and goal)",
  ],
  write: "Also allow it to log and delete meals for me",
  notice: "Data it reads is sent to that assistant's provider and handled under their privacy policy. You can revoke access in the NextBody app.",
  allow: "Allow",
  deny: "Deny",
  clientFallback: "This assistant",
  genericError: "Something went wrong. Try again.",
  invalidEmail: "Enter the email for your NextBody account.",
  invalidCode: "Enter the 6-digit code.",
};

const zh: ConsentCopy = {
  title: "允许访问",
  kicker: "NextBody",
  missingId: "这个链接缺少授权编号。请从你的助手重新开始。",
  notConfigured: "这个页面尚未配置。",
  signInTitle: "登录 NextBody",
  signInLede: "请使用与 NextBody App 相同的账号。",
  emailLabel: "邮箱",
  emailPlaceholder: "you@example.com",
  sendCode: "把验证码发到邮箱",
  codeLabel: "6 位验证码",
  codePlaceholder: "000000",
  verify: "继续",
  differentEmail: "换一个邮箱",
  apple: "通过 Apple 继续",
  google: "通过 Google 继续",
  or: "或",
  noAccount: "这个邮箱还没有 NextBody 账号。请先在 App 里创建。",
  codeSent: "请输入我们发送到以下邮箱的验证码",
  consentTitle: "允许这个助手",
  signedIn: "当前登录",
  notYou: "不是你？退出登录",
  readsTitle: "它可以读取",
  reads: ["睡眠", "心率与心率变异性", "压力、步数、皮温与食物反应点", "身体电量", "训练负荷", "热量与饮食", "体重与身体成分", "运动记录、平衡检查及健康资料（身高、生日和目标）"],
  write: "同时允许它为我记录和删除饮食",
  notice: "它读取的数据会发送给该助手的服务商，并按其隐私政策处理。你可以在 NextBody App 里撤销访问。",
  allow: "允许",
  deny: "拒绝",
  clientFallback: "这个助手",
  genericError: "出了点问题。请再试一次。",
  invalidEmail: "请输入你的 NextBody 账号邮箱。",
  invalidCode: "请输入 6 位验证码。",
};

const AUTHORIZATION_ID_KEY = "nextbody.authorization_id";

interface PageState {
  supabase: SupabaseClient;
  authorizationId: string;
}

let copy: ConsentCopy = en;
let state: PageState | null = null;
let working = false;
let alertNode: HTMLElement | null = null;

function chooseCopy(): ConsentCopy {
  if (navigator.language.toLowerCase().startsWith("zh")) return zh;
  return en;
}

function element(tag: string, className: string, value: string): HTMLElement {
  const node = document.createElement(tag);
  if (className) node.className = className;
  node.textContent = value;
  return node;
}

function setAlert(message: string): void {
  if (alertNode) alertNode.textContent = message;
}

function setBusy(busy: boolean): void {
  const root = document.querySelector("#app");
  if (!root) return;
  const controls = root.querySelectorAll("button, input");
  for (const node of controls) {
    if (node instanceof HTMLButtonElement || node instanceof HTMLInputElement) node.disabled = busy;
  }
}

function begin(): boolean {
  if (working) return false;
  working = true;
  setBusy(true);
  setAlert("");
  return true;
}

function fail(message: string): void {
  working = false;
  setBusy(false);
  setAlert(message);
}

function idle(): void {
  working = false;
  setBusy(false);
}

function mount(node: Node): void {
  const app = document.querySelector("#app");
  if (!app) return;
  app.replaceChildren(node);
  alertNode = app.querySelector(".alert");
}

function alertLine(): HTMLParagraphElement {
  const node = document.createElement("p");
  node.className = "alert";
  node.setAttribute("role", "alert");
  return node;
}

function readConfig(): NextbodyConfig | null {
  const config = window.NEXTBODY_CONFIG;
  if (!config?.supabaseUrl || !config.supabaseKey) return null;
  return config;
}

function readAuthorizationId(): string | null {
  const fromUrl = new URL(window.location.href).searchParams.get("authorization_id");
  if (fromUrl) {
    sessionStorage.setItem(AUTHORIZATION_ID_KEY, fromUrl);
    return fromUrl;
  }
  return sessionStorage.getItem(AUTHORIZATION_ID_KEY);
}

// Supabase appends the PKCE code on return and can replace the query string.
function redirectTarget(authorizationId: string): string {
  const url = new URL(window.location.href);
  url.searchParams.set("authorization_id", authorizationId);
  url.searchParams.delete("code");
  url.searchParams.delete("error");
  url.searchParams.delete("error_description");
  url.hash = "";
  return url.toString();
}

function oauthErrorFromUrl(): string | null {
  const params = new URL(window.location.href).searchParams;
  return params.get("error_description") || params.get("error");
}

function isMissingAccount(error: AuthError): boolean {
  const code = (error.code ?? "").toLowerCase();
  const message = error.message.toLowerCase();
  return code === "user_not_found"
    || code === "otp_disabled"
    || code === "signup_disabled"
    || message.includes("signups not allowed")
    || message.includes("user not found");
}

function needsConsent(data: OAuthAuthorizationDetails | OAuthRedirect): data is OAuthAuthorizationDetails {
  return "authorization_id" in data;
}

function renderNotice(heading: string, message: string): void {
  const page = document.createElement("div");
  page.className = "stack";
  page.append(element("p", "kicker", copy.kicker), element("h1", "", heading), element("p", "lede", message));
  mount(page);
}

function renderSignIn(initialAlert = ""): void {
  const email = document.createElement("input");
  email.type = "email";
  email.name = "email";
  email.autocomplete = "username";
  email.required = true;
  email.placeholder = copy.emailPlaceholder;
  email.spellcheck = false;

  const form = document.createElement("form");
  form.className = "stack tight";
  form.addEventListener("submit", function onEmailSubmit(event: SubmitEvent): void {
    event.preventDefault();
    const value = email.value.trim();
    if (!value.includes("@")) {
      setAlert(copy.invalidEmail);
      return;
    }
    void sendEmailCode(value);
  });
  const label = document.createElement("label");
  label.append(document.createTextNode(copy.emailLabel), email);
  const submit = document.createElement("button");
  submit.type = "submit";
  submit.className = "primary";
  submit.textContent = copy.sendCode;
  form.append(label, submit, alertLine());

  const apple = document.createElement("button");
  apple.type = "button";
  apple.className = "ghost";
  apple.textContent = copy.apple;
  apple.addEventListener("click", function onApple(): void {
    void continueWith("apple");
  });
  const google = document.createElement("button");
  google.type = "button";
  google.className = "ghost";
  google.textContent = copy.google;
  google.addEventListener("click", function onGoogle(): void {
    void continueWith("google");
  });

  // Web sign-in with Apple or Google needs its own Services ID / web client in Supabase Auth;
  // a provider stays hidden until the build lists it.
  const providers = readConfig()?.providers ?? [];
  const card = document.createElement("section");
  card.className = "card stack";
  card.append(form);
  if (providers.includes("apple") || providers.includes("google")) card.append(element("p", "divider", copy.or));
  if (providers.includes("apple")) card.append(apple);
  if (providers.includes("google")) card.append(google);

  const page = document.createElement("div");
  page.className = "stack";
  page.append(
    element("p", "kicker", copy.kicker),
    element("h1", "", copy.signInTitle),
    element("p", "lede", copy.signInLede),
    card,
  );
  mount(page);
  setAlert(initialAlert);
  email.focus();
}

function renderCode(emailAddress: string): void {
  const token = document.createElement("input");
  token.type = "text";
  token.name = "token";
  token.inputMode = "numeric";
  token.autocomplete = "one-time-code";
  token.maxLength = 6;
  token.placeholder = copy.codePlaceholder;
  token.spellcheck = false;

  const form = document.createElement("form");
  form.className = "stack tight";
  form.addEventListener("submit", function onCodeSubmit(event: SubmitEvent): void {
    event.preventDefault();
    const value = token.value.trim();
    if (!/^\d{6}$/.test(value)) {
      setAlert(copy.invalidCode);
      return;
    }
    void verifyEmailCode(emailAddress, value);
  });
  const label = document.createElement("label");
  label.append(document.createTextNode(copy.codeLabel), token);
  const submit = document.createElement("button");
  submit.type = "submit";
  submit.className = "primary";
  submit.textContent = copy.verify;
  form.append(label, submit, alertLine());

  const back = document.createElement("button");
  back.type = "button";
  back.className = "link";
  back.textContent = copy.differentEmail;
  back.addEventListener("click", function onDifferentEmail(): void {
    renderSignIn();
  });

  const sent = document.createElement("p");
  sent.className = "lede";
  sent.append(document.createTextNode(`${copy.codeSent} `));
  const address = document.createElement("strong");
  address.textContent = emailAddress;
  sent.append(address);

  const card = document.createElement("section");
  card.className = "card stack";
  card.append(sent, form, back);

  const page = document.createElement("div");
  page.className = "stack";
  page.append(element("p", "kicker", copy.kicker), element("h1", "", copy.signInTitle), card);
  mount(page);
  token.focus();
}

function renderConsent(session: Session, details: OAuthAuthorizationDetails): void {
  const clientName = (details.client.name ?? "").trim() || copy.clientFallback;
  const clientUri = (details.client.uri ?? "").trim();
  const email = session.user.email || details.user.email;

  const who = document.createElement("p");
  who.className = "who";
  if (email) who.append(document.createTextNode(`${copy.signedIn} ${email}`));
  const signOutButton = document.createElement("button");
  signOutButton.type = "button";
  signOutButton.className = "link";
  signOutButton.textContent = copy.notYou;
  signOutButton.addEventListener("click", function onSignOut(): void {
    void signOut();
  });
  who.append(signOutButton);

  const list = document.createElement("ul");
  list.className = "reads";
  for (const item of copy.reads) {
    const li = document.createElement("li");
    li.textContent = item;
    list.append(li);
  }

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.id = "can-write";
  const writeLabel = document.createElement("label");
  writeLabel.className = "check";
  writeLabel.append(checkbox, element("span", "", copy.write));

  const allow = document.createElement("button");
  allow.type = "button";
  allow.className = "primary";
  allow.textContent = copy.allow;
  allow.addEventListener("click", function onAllow(): void {
    void allowAccess(details, checkbox.checked);
  });
  const deny = document.createElement("button");
  deny.type = "button";
  deny.className = "ghost";
  deny.textContent = copy.deny;
  deny.addEventListener("click", function onDeny(): void {
    void denyAccess();
  });
  const actions = document.createElement("div");
  actions.className = "actions";
  actions.append(allow, deny);

  const card = document.createElement("section");
  card.className = "card stack";
  card.append(element("h2", "", clientName));
  if (clientUri) card.append(element("p", "client-uri", clientUri));
  card.append(who, element("p", "field-label", copy.readsTitle), list, writeLabel, element("p", "note", copy.notice), alertLine(), actions);

  const page = document.createElement("div");
  page.className = "stack";
  page.append(element("p", "kicker", copy.kicker), element("h1", "", copy.consentTitle), card);
  mount(page);
}

async function sendEmailCode(email: string): Promise<void> {
  if (!state || !begin()) return;
  const { error } = await state.supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });
  if (error) {
    fail(isMissingAccount(error) ? copy.noAccount : error.message);
    return;
  }
  idle();
  renderCode(email);
}

async function verifyEmailCode(email: string, token: string): Promise<void> {
  if (!state || !begin()) return;
  const { data, error } = await state.supabase.auth.verifyOtp({
    email,
    token,
    type: "email",
  });
  if (error || !data.session) {
    fail(error?.message ?? copy.genericError);
    return;
  }
  await openAuthorization(data.session);
}

async function continueWith(provider: "apple" | "google"): Promise<void> {
  if (!state || !begin()) return;
  const { data, error } = await state.supabase.auth.signInWithOAuth({
    provider,
    options: { redirectTo: redirectTarget(state.authorizationId) },
  });
  if (error) {
    fail(error.message);
    return;
  }
  if (data.url) window.location.assign(data.url);
}

async function signOut(): Promise<void> {
  if (!state || !begin()) return;
  const { error } = await state.supabase.auth.signOut();
  if (error) {
    fail(error.message);
    return;
  }
  idle();
  renderSignIn();
}

async function openAuthorization(session: Session): Promise<void> {
  if (!state) return;
  const result = await state.supabase.auth.oauth.getAuthorizationDetails(state.authorizationId);
  if (result.error || !result.data) {
    fail(result.error?.message ?? copy.genericError);
    return;
  }
  // Supabase skips consent while its own grant exists. That grant only outlives our
  // mcp_grants row if the app revoked in the wrong order, and the redirect does not name the
  // client, so the app lists that state and its DISCONNECT clears both.
  if (!needsConsent(result.data)) {
    window.location.assign(result.data.redirect_url);
    return;
  }
  idle();
  renderConsent(session, result.data);
}

async function allowAccess(details: OAuthAuthorizationDetails, canWrite: boolean): Promise<void> {
  if (!state || !begin()) return;
  const recorded = await state.supabase.rpc("record_mcp_grant", {
    p_client_id: details.client.id,
    p_client_name: details.client.name ?? "",
    p_can_write: canWrite,
  });
  if (recorded.error) {
    fail(recorded.error.message);
    return;
  }
  const approved = await state.supabase.auth.oauth.approveAuthorization(state.authorizationId, {
    skipBrowserRedirect: true,
  });
  if (approved.error || !approved.data?.redirect_url) {
    fail(approved.error?.message ?? copy.genericError);
    return;
  }
  window.location.assign(approved.data.redirect_url);
}

async function denyAccess(): Promise<void> {
  if (!state || !begin()) return;
  const denied = await state.supabase.auth.oauth.denyAuthorization(state.authorizationId, {
    skipBrowserRedirect: true,
  });
  if (denied.error || !denied.data?.redirect_url) {
    fail(denied.error?.message ?? copy.genericError);
    return;
  }
  window.location.assign(denied.data.redirect_url);
}

async function boot(): Promise<void> {
  copy = chooseCopy();
  document.title = copy.title;
  document.documentElement.lang = copy === zh ? "zh-Hans" : "en";
  const config = readConfig();
  if (!config) {
    renderNotice(copy.title, copy.notConfigured);
    return;
  }
  const authorizationId = readAuthorizationId();
  if (!authorizationId) {
    renderNotice(copy.title, copy.missingId);
    return;
  }
  const supabase = createClient(config.supabaseUrl, config.supabaseKey, {
    auth: {
      flowType: "pkce",
      detectSessionInUrl: true,
      persistSession: true,
    },
  });
  state = { supabase, authorizationId };
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    renderNotice(copy.signInTitle, error.message);
    return;
  }
  if (!data.session) {
    renderSignIn(oauthErrorFromUrl() ?? "");
    return;
  }
  await openAuthorization(data.session);
}

async function main(): Promise<void> {
  try {
    await boot();
  } catch (error) {
    const message = error instanceof Error ? error.message : en.genericError;
    renderNotice(copy.title, message);
  }
}

void main();
