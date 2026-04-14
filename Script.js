const MANAGED_GROUP_NAMES = [
  "UnityGlobal",
  "UnityWeb",
  "UnityHub",
  "UnityEditor",
  "UnityDownload",
  "UnityChina",
  "SteamCommunity",
  "SteamMainland",
  "SteamDownload",
];

function unique(items) {
  const seen = new Set();
  const result = [];

  for (const item of items) {
    if (!item || seen.has(item)) continue;
    seen.add(item);
    result.push(item);
  }

  return result;
}

function pickGroupNames(groups, preferred) {
  const names = groups
    .map((group) => group && group.name)
    .filter((name) => name && !MANAGED_GROUP_NAMES.includes(name));

  const preferredNames = preferred.filter((name) => names.includes(name));
  const restNames = names.filter((name) => !preferred.includes(name));
  return unique([...preferredNames, ...restNames]);
}

function pickProxyNames(proxies) {
  return unique(
    (proxies || [])
      .map((proxy) => proxy && proxy.name)
      .filter(Boolean)
  );
}

function upsertSelectGroup(groups, name, proxies) {
  const nextGroups = groups.filter((group) => group && group.name !== name);
  nextGroups.unshift({
    name,
    type: "select",
    proxies,
  });
  return nextGroups;
}

function prependRules(config, desiredRules) {
  const existingRules = Array.isArray(config.rules) ? config.rules : [];
  const filteredRules = existingRules.filter((rule) => !desiredRules.includes(rule));
  config.rules = [...desiredRules, ...filteredRules];
}

function main(config) {
  const nextConfig = config || {};
  const proxyGroups = Array.isArray(nextConfig["proxy-groups"]) ? nextConfig["proxy-groups"] : [];
  const proxies = Array.isArray(nextConfig.proxies) ? nextConfig.proxies : [];

  const preferredGroups = pickGroupNames(proxyGroups, [
    "\u81ea\u52a8\u9009\u62e9",
    "\u2611\ufe0f \u81ea\u52a8\u9009\u62e9",
    "Auto Select",
    "\u6545\u969c\u8f6c\u79fb",
    "Fallback",
  ]);
  const proxyNames = pickProxyNames(proxies);

  const unityGlobalChoices = unique([
    ...preferredGroups,
    ...proxyNames,
    "DIRECT",
  ]);
  const unityHubChoices = unique([
    "UnityGlobal",
    ...unityGlobalChoices,
  ]);
  const unityWebChoices = unique([
    "UnityGlobal",
    ...unityGlobalChoices,
  ]);
  const unityEditorChoices = unique([
    "UnityGlobal",
    ...unityGlobalChoices,
  ]);
  const unityDownloadChoices = unique([
    "UnityGlobal",
    ...unityGlobalChoices,
  ]);
  const unityChinaChoices = unique([
    "REJECT",
    "UnityGlobal",
    "DIRECT",
    ...preferredGroups,
    ...proxyNames,
  ]);
  const steamCommunityChoices = unique([
    ...preferredGroups,
    ...proxyNames,
    "DIRECT",
  ]);
  const steamMainlandChoices = unique([
    "DIRECT",
    ...preferredGroups,
    ...proxyNames,
  ]);
  const steamDownloadChoices = unique([
    "DIRECT",
    ...preferredGroups,
    ...proxyNames,
  ]);

  let nextGroups = proxyGroups;
  nextGroups = upsertSelectGroup(nextGroups, "SteamDownload", steamDownloadChoices);
  nextGroups = upsertSelectGroup(nextGroups, "SteamMainland", steamMainlandChoices);
  nextGroups = upsertSelectGroup(nextGroups, "SteamCommunity", steamCommunityChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityChina", unityChinaChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityDownload", unityDownloadChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityEditor", unityEditorChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityWeb", unityWebChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityHub", unityHubChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityGlobal", unityGlobalChoices);
  nextConfig["proxy-groups"] = nextGroups;

  const unityRules = [
    "DOMAIN-SUFFIX,unitychina.cn,UnityChina",
    "DOMAIN-SUFFIX,unity.cn,UnityChina",
    "DOMAIN-SUFFIX,u3d.cn,UnityChina",
    "DOMAIN,download.unity3d.com,UnityDownload",
    "DOMAIN,beta.unity3d.com,UnityDownload",
    "DOMAIN,dl.google.com,UnityDownload",
    "DOMAIN,go.microsoft.com,UnityDownload",
    "DOMAIN,unity-connect-prd.storage.googleapis.com,UnityEditor",
    "DOMAIN,storage.googleapis.com,UnityEditor",
    "DOMAIN,upm-cdn.unity.com,UnityEditor",
    "DOMAIN,cdn.packages.unity.com,UnityEditor",
    "DOMAIN,download.packages.unity.com,UnityEditor",
    "DOMAIN,private.download.packages.unity.com,UnityEditor",
    "DOMAIN,packages.unity.com,UnityEditor",
    "DOMAIN,packages-v2.unity.com,UnityEditor",
    "DOMAIN,config.uca.cloud.unity3d.com,UnityEditor",
    "DOMAIN,analytics.cloud.unity3d.com,UnityEditor",
    "DOMAIN,cdp.cloud.unity3d.com,UnityEditor",
    "DOMAIN,developer.cloud.unity3d.com,UnityEditor",
    "DOMAIN,perf.cloud.unity3d.com,UnityEditor",
    "DOMAIN,perf-events.cloud.unity3d.com,UnityEditor",
    "DOMAIN,api2.amplitude.com,UnityEditor",
    "DOMAIN,assetstore.unity.com,UnityWeb",
    "DOMAIN,kharma.unity3d.com,UnityWeb",
    "DOMAIN,unity-assetstorev2-prd.storage.googleapis.com,UnityWeb",
    "DOMAIN,id.unity.com,UnityWeb",
    "DOMAIN,api.unity.com,UnityWeb",
    "DOMAIN,login.unity.com,UnityWeb",
    "DOMAIN,accounts.unity3d.com,UnityWeb",
    "DOMAIN,services.unity.com,UnityHub",
    "DOMAIN,license.unity3d.com,UnityHub",
    "DOMAIN,activation.unity3d.com,UnityHub",
    "DOMAIN,public-cdn.cloud.unity3d.com,UnityHub",
    "DOMAIN,core.cloud.unity3d.com,UnityHub",
    "DOMAIN,live-platform-api.prd.ld.unity3d.com,UnityHub",
    "DOMAIN,api.hub-proxy.unity3d.com,UnityHub",
    "DOMAIN,core.hub-proxy.unity3d.com,UnityHub",
    "DOMAIN,config.hub-proxy.unity3d.com,UnityHub",
    "DOMAIN,learn.unity.com,UnityHub",
    "DOMAIN-SUFFIX,hub-proxy.unity3d.com,UnityHub",
    "DOMAIN-SUFFIX,unity.com,UnityHub",
    "DOMAIN-SUFFIX,unity3d.com,UnityHub",
    "DOMAIN-SUFFIX,plasticscm.com,UnityHub",
  ];
  const steamRules = [
    "DOMAIN-SUFFIX,steamcommunity.com,SteamCommunity",
    "DOMAIN-SUFFIX,steam-chat.com,SteamCommunity",
    "DOMAIN-SUFFIX,steamusercontent.com,SteamCommunity",
    "DOMAIN,community.steamstatic.com,SteamCommunity",
    "DOMAIN,avatars.steamstatic.com,SteamCommunity",
    "DOMAIN,shared.fastly.steamstatic.com,SteamCommunity",
    "DOMAIN-SUFFIX,steamcommunity-a.akamaihd.net,SteamCommunity",
    "DOMAIN-SUFFIX,steamuserimages-a.akamaihd.net,SteamCommunity",
    "DOMAIN,store.steampowered.com,SteamMainland",
    "DOMAIN,help.steampowered.com,SteamMainland",
    "DOMAIN,api.steampowered.com,SteamMainland",
    "DOMAIN,store.fastly.steamstatic.com,SteamMainland",
    "DOMAIN,clientconfig.akamai.steamstatic.com,SteamDownload",
    "DOMAIN-SUFFIX,steampipe-partner.akamaized.net,SteamDownload",
    "DOMAIN-KEYWORD,steamcdn,SteamDownload",
    "DOMAIN-KEYWORD,steampipe,SteamDownload",
    "DOMAIN-KEYWORD,steamcontent,SteamDownload",
    "DOMAIN-KEYWORD,steamserver,SteamDownload",
    "DOMAIN-SUFFIX,steamcdn-a.akamaihd.net,SteamDownload",
    "DOMAIN-SUFFIX,steampipe.akamaized.net,SteamDownload",
    "DOMAIN-SUFFIX,steamcontent.com,SteamDownload",
    "DOMAIN-SUFFIX,steamserver.net,SteamDownload",
    "DOMAIN-SUFFIX,steampowered.com,SteamMainland",
    "DOMAIN-SUFFIX,steamstatic.com,SteamMainland",
    "DOMAIN-SUFFIX,cdn.steamstatic.com,SteamMainland",
    "DOMAIN-SUFFIX,cdn.cloudflare.steamstatic.com,SteamMainland",
  ];

  prependRules(nextConfig, [...unityRules, ...steamRules]);
  return nextConfig;
}
