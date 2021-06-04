const PepeToken = artifacts.require("PepeToken");
const Utils = artifacts.require("Utils");
const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer) {
  await deployer.deploy(Utils);
  await deployer.link(Utils, PepeToken);
  const proxyAddress = "0xd1F12DbFa8D4A9319eA4e8E8deB54056ABD8a23e";
  await upgradeProxy(proxyAddress, PepeToken, {
    deployer,
    unsafeAllow: ["external-library-linking"],
  });
};
