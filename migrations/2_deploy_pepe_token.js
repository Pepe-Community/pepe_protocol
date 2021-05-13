const PepeToken = artifacts.require("PepeToken");
const Utils = artifacts.require("Utils");

module.exports = async function (deployer) {
  await deployer.deploy(Utils);
  await deployer.link(Utils, PepeToken);
  await deployer.deploy(
    PepeToken,
    "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
  );
};
