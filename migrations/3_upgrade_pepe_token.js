const PepeToken = artifacts.require("PepeToken");
const Utils = artifacts.require("Utils");
const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer) {
  await deployer.deploy(Utils);
  await deployer.link(Utils, PepeToken);
  const proxyAddress = "0xF8519dE1923A038356C779a3a2Dd3be447A7d30B";
  await upgradeProxy(proxyAddress, PepeToken, {
    deployer,
    unsafeAllow: ["external-library-linking"],
  });
};
