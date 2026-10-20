interface ClientStep {
  title: string;
  body: string;
  snippet: string | null;
}

interface LandingCopy {
  title: string;
  kicker: string;
  headline: string;
  lede: string;
  urlLabel: string;
  url: string;
  copy: string;
  copied: string;
  copyFailed: string;
  stepsTitle: string;
  clients: ClientStep[];
  revoke: string;
  share: string;
}

const en: LandingCopy = {
  title: "NextBody",
  kicker: "NextBody",
  headline: "Connect your AI assistant to your own NextBody data",
  lede: "ChatGPT, Claude, Cursor, and Grok can read your HOOP band data only after you sign in and approve access.",
  urlLabel: "MCP server URL",
  url: "https://mcp.nextbody.ai/mcp",
  copy: "Copy",
  copied: "Copied",
  copyFailed: "Select the URL and copy it",
  stepsTitle: "Add it to your assistant",
  clients: [
    {
      title: "ChatGPT",
      body: "Add a custom connector, or a developer-mode app, with this URL. When asked, sign in with NextBody.",
      snippet: null,
    },
    {
      title: "Claude.ai and Claude Desktop",
      body: "Open Settings → Connectors → Add custom connector, then paste the URL.",
      snippet: null,
    },
    {
      title: "Claude Code",
      body: "Run this in your terminal:",
      snippet: "claude mcp add --transport http nextbody https://mcp.nextbody.ai/mcp",
    },
    {
      title: "Cursor",
      body: "Add this to ~/.cursor/mcp.json:",
      snippet: '{"mcpServers":{"nextbody":{"url":"https://mcp.nextbody.ai/mcp"}}}',
    },
    {
      title: "Grok",
      body: "If your Grok client supports remote MCP servers, add the same URL.",
      snippet: null,
    },
  ],
  revoke: "You can revoke access any time in the NextBody app (Profile → AI assistants).",
  share: "Data an assistant reads is shared with that assistant's provider.",
};

const zh: LandingCopy = {
  title: "NextBody",
  kicker: "NextBody",
  headline: "把 AI 助手接到你自己的 NextBody 数据",
  lede: "只有在你登录并同意之后，ChatGPT、Claude、Cursor 和 Grok 才能读取你的 HOOP 手环数据。",
  urlLabel: "MCP 服务器地址",
  url: "https://mcp.nextbody.ai/mcp",
  copy: "复制",
  copied: "已复制",
  copyFailed: "请选中地址后手动复制",
  stepsTitle: "添加到助手",
  clients: [
    {
      title: "ChatGPT",
      body: "添加自定义连接器，或在开发者模式里添加应用，填入这个地址。出现登录时，使用 NextBody 账号。",
      snippet: null,
    },
    {
      title: "Claude.ai 和 Claude Desktop",
      body: "打开 设置 → 连接器 → 添加自定义连接器，然后粘贴地址。",
      snippet: null,
    },
    {
      title: "Claude Code",
      body: "在终端运行：",
      snippet: "claude mcp add --transport http nextbody https://mcp.nextbody.ai/mcp",
    },
    {
      title: "Cursor",
      body: "把下面的内容写入 ~/.cursor/mcp.json：",
      snippet: '{"mcpServers":{"nextbody":{"url":"https://mcp.nextbody.ai/mcp"}}}',
    },
    {
      title: "Grok",
      body: "如果你的 Grok 客户端支持远程 MCP 服务器，添加同一个地址。",
      snippet: null,
    },
  ],
  revoke: "你可以随时在 NextBody App 里撤销访问（个人资料 → AI 助手）。",
  share: "助手读取的数据会分享给该助手的服务商。",
};

function chooseCopy(): LandingCopy {
  if (navigator.language.toLowerCase().startsWith("zh")) return zh;
  return en;
}

function element(tag: string, className: string, value: string): HTMLElement {
  const node = document.createElement(tag);
  if (className) node.className = className;
  node.textContent = value;
  return node;
}

async function copyUrl(button: HTMLButtonElement, copy: LandingCopy): Promise<void> {
  try {
    await navigator.clipboard.writeText(copy.url);
    button.textContent = copy.copied;
  } catch {
    button.textContent = copy.copyFailed;
  }
  window.setTimeout(function restoreLabel(): void {
    button.textContent = copy.copy;
  }, 1600);
}

function renderClient(step: ClientStep): HTMLElement {
  const card = document.createElement("article");
  card.className = "card stack tight";
  card.append(element("h2", "", step.title), element("p", "", step.body));
  if (step.snippet) {
    const snippet = document.createElement("pre");
    snippet.textContent = step.snippet;
    card.append(snippet);
  }
  return card;
}

function render(copy: LandingCopy): void {
  document.title = copy.title;
  document.documentElement.lang = copy === zh ? "zh-Hans" : "en";
  const app = document.querySelector("#app");
  if (!app) return;

  const url = element("p", "url", copy.url);
  const copyButton = document.createElement("button");
  copyButton.type = "button";
  copyButton.className = "copy";
  copyButton.textContent = copy.copy;
  copyButton.addEventListener("click", function onCopy(): void {
    void copyUrl(copyButton, copy);
  });

  const urlLine = document.createElement("div");
  urlLine.className = "url-line";
  urlLine.append(url, copyButton);

  const urlCard = document.createElement("section");
  urlCard.className = "card stack tight";
  urlCard.append(element("p", "field-label", copy.urlLabel), urlLine);

  const steps = document.createElement("section");
  steps.className = "stack section";
  steps.append(element("h2", "", copy.stepsTitle));
  for (const client of copy.clients) steps.append(renderClient(client));

  const page = document.createElement("div");
  page.className = "stack";
  page.append(
    element("p", "kicker", copy.kicker),
    element("h1", "", copy.headline),
    element("p", "lede", copy.lede),
    urlCard,
    steps,
    element("p", "note", copy.revoke),
    element("p", "note", copy.share),
  );
  app.replaceChildren(page);
}

function main(): void {
  render(chooseCopy());
}

main();
