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
    .filter((name) =>
      name &&
      name !== "UnityChina" &&
      name !== "UnityDownload" &&
      name !== "UnityHub" &&
      name !== "SteamCommunity" &&
      name !== "SteamMainland" &&
      name !== "SteamDownload"
    );

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
    "自动选择",
    "♻️ 自动选择",
    "Auto Select",
    "故障转移",
    "Fallback",
  ]);
  const proxyNames = pickProxyNames(proxies);

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
  const unityChinaChoices = unique([
    "REJECT",
    "DIRECT",
    ...preferredGroups,
    ...proxyNames,
  ]);
  const unityDownloadChoices = unique([
    ...preferredGroups,
    ...proxyNames,
    "DIRECT",
  ]);
  const unityHubChoices = unique([
    ...preferredGroups,
    ...proxyNames,
    "DIRECT",
  ]);

  let nextGroups = proxyGroups;
  nextGroups = upsertSelectGroup(nextGroups, "SteamDownload", steamDownloadChoices);
  nextGroups = upsertSelectGroup(nextGroups, "SteamMainland", steamMainlandChoices);
  nextGroups = upsertSelectGroup(nextGroups, "SteamCommunity", steamCommunityChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityChina", unityChinaChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityDownload", unityDownloadChoices);
  nextGroups = upsertSelectGroup(nextGroups, "UnityHub", unityHubChoices);
  nextConfig["proxy-groups"] = nextGroups;

  const unityHubRules = [
    "DOMAIN-SUFFIX,unitychina.cn,UnityChina",
    "DOMAIN-SUFFIX,unity.cn,UnityChina",
    "DOMAIN-SUFFIX,u3d.cn,UnityChina",
    "DOMAIN,download.unity3d.com,UnityDownload",
    "DOMAIN,beta.unity3d.com,UnityDownload",
    "DOMAIN,cdn.packages.unity.com,UnityDownload",
    "DOMAIN,download.packages.unity.com,UnityDownload",
    "DOMAIN,private.download.packages.unity.com,UnityDownload",
    "DOMAIN,services.unity.com,UnityHub",
    "DOMAIN,api.unity.com,UnityHub",
    "DOMAIN,id.unity.com,UnityHub",
    "DOMAIN,login.unity.com,UnityHub",
    "DOMAIN,accounts.unity3d.com,UnityHub",
    "DOMAIN,license.unity3d.com,UnityHub",
    "DOMAIN,activation.unity3d.com,UnityHub",
    "DOMAIN,assetstore.unity.com,UnityHub",
    "DOMAIN,packages.unity.com,UnityHub",
    "DOMAIN,packages-v2.unity.com,UnityHub",
    "DOMAIN,public-cdn.cloud.unity3d.com,UnityHub",
    "DOMAIN,core.cloud.unity3d.com,UnityHub",
    "DOMAIN,live-platform-api.prd.ld.unity3d.com,UnityHub",
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

  prependRules(nextConfig, [...unityHubRules, ...steamRules]);
  return nextConfig;
}
