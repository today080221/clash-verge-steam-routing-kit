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

  let nextGroups = proxyGroups;
  nextGroups = upsertSelectGroup(nextGroups, "SteamDownload", steamDownloadChoices);
  nextGroups = upsertSelectGroup(nextGroups, "SteamMainland", steamMainlandChoices);
  nextGroups = upsertSelectGroup(nextGroups, "SteamCommunity", steamCommunityChoices);
  nextConfig["proxy-groups"] = nextGroups;

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

  prependRules(nextConfig, steamRules);
  return nextConfig;
}
