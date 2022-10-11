const SET = artifacts.require("ScubrEngagementToken");
const ScubrVideoToken = artifacts.require("ScubrVideoToken");

module.exports = async function (deployer) {
    await deployer.deploy(SET);
    const token = await SET.deployed();

    await deployer.deploy(ScubrVideoToken, token.address);
}