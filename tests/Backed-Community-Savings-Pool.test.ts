
import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

const contractName = "Backed-Community-Savings-Pool";

describe("Bitcoin-Backed Community Savings Pool with Analytics", () => {
  beforeEach(() => {
    // Initialize pool before each test
    simnet.callPublicFn(contractName, "initialize-pool", [], deployer);
  });

  describe("Basic Pool Functionality", () => {
    it("ensures simnet is well initialised", () => {
      expect(simnet.blockHeight).toBeDefined();
    });

    it("initializes pool correctly", () => {
      const poolInfo = simnet.callReadOnlyFn(contractName, "get-pool-info", [], deployer);
      expect(poolInfo.result).toBeOk(
        expect.objectContaining({
          active: true,
          "total-deposits": "u0",
          "member-count": "u0",
        })
      );
    });

    it("allows members to join pool", () => {
      const joinResult = simnet.callPublicFn(
        contractName,
        "join-pool",
        [Cl.uint(1000000)], // 1M uSTX (Bronze tier)
        wallet1
      );
      expect(joinResult.result).toBeOk("u1"); // Bronze tier

      const memberInfo = simnet.callReadOnlyFn(contractName, "get-member-info", [wallet1], deployer);
      expect(memberInfo.result).toBeOk(
        expect.objectContaining({
          "total-deposited": "u1000000",
          tier: "u1",
        })
      );
    });
  });

  describe("Analytics System", () => {
    beforeEach(() => {
      // Add some members and activity for analytics testing
      simnet.callPublicFn(contractName, "join-pool", [Cl.uint(1000000)], wallet1); // Bronze
      simnet.callPublicFn(contractName, "join-pool", [Cl.uint(5000000)], wallet2); // Silver
      simnet.callPublicFn(contractName, "join-pool", [Cl.uint(10000000)], wallet3); // Gold
    });

    it("tracks pool growth summary correctly", () => {
      const growthSummary = simnet.callReadOnlyFn(
        contractName,
        "get-pool-growth-summary",
        [],
        deployer
      );
      
      expect(growthSummary.result).toBeOk(
        expect.objectContaining({
          "total-members": "u3",
          "total-deposits": "u16000000", // 1M + 5M + 10M
          "total-transactions": "u3",
          "analytics-enabled": true,
        })
      );
    });

    it("calculates pool health score", () => {
      const healthScore = simnet.callReadOnlyFn(
        contractName,
        "calculate-pool-health-score",
        [],
        deployer
      );
      
      expect(healthScore.result).toBeOk(
        expect.objectContaining({
          "member-diversity-score": expect.any(Number),
          "deposit-stability-score": expect.any(Number),
          "interest-health-score": expect.any(Number),
          "overall-health-score": expect.any(Number),
        })
      );
    });

    it("provides member analytics summary", () => {
      const memberSummary = simnet.callReadOnlyFn(
        contractName,
        "get-member-analytics-summary",
        [wallet2],
        deployer
      );
      
      expect(memberSummary.result).toBeOk(
        expect.objectContaining({
          "member-tier": "u2", // Silver tier
          "total-deposited": "u5000000",
          "monthly-deposits": "u1",
          "monthly-deposited-amount": "u5000000",
        })
      );
    });

    it("generates performance reports", () => {
      const reportResult = simnet.callPublicFn(
        contractName,
        "generate-performance-report",
        [Cl.uint(1)],
        deployer
      );
      
      expect(reportResult.result).toBeOk(true);

      const metrics = simnet.callReadOnlyFn(
        contractName,
        "get-performance-metrics",
        [Cl.uint(1)],
        deployer
      );
      
      expect(metrics.result).toBeOk(
        expect.objectContaining({
          "growth-rate": expect.any(Number),
          "retention-rate": expect.any(Number),
          "average-member-value": expect.any(Number),
        })
      );
    });

    it("tracks analytics across deposits", () => {
      // Make additional deposits
      simnet.callPublicFn(contractName, "deposit", [Cl.uint(500000)], wallet1);
      simnet.callPublicFn(contractName, "deposit", [Cl.uint(1000000)], wallet2);
      
      const growthSummary = simnet.callReadOnlyFn(
        contractName,
        "get-pool-growth-summary",
        [],
        deployer
      );
      
      expect(growthSummary.result).toBeOk(
        expect.objectContaining({
          "total-deposits": "u17500000", // Previous + additional deposits
          "total-transactions": "u5", // 3 initial joins + 2 deposits
        })
      );
    });

    it("allows toggling analytics", () => {
      const toggleResult = simnet.callPublicFn(
        contractName,
        "toggle-analytics",
        [],
        deployer
      );
      
      expect(toggleResult.result).toBeOk(false); // Analytics should be disabled
      
      // Toggle back
      const toggleBackResult = simnet.callPublicFn(
        contractName,
        "toggle-analytics",
        [],
        deployer
      );
      
      expect(toggleBackResult.result).toBeOk(true); // Analytics should be enabled
    });

    it("prevents unauthorized analytics toggle", () => {
      const toggleResult = simnet.callPublicFn(
        contractName,
        "toggle-analytics",
        [],
        wallet1 // Not the contract caller
      );
      
      expect(toggleResult.result).toBeErr(100); // ERR-NOT-AUTHORIZED
    });

    it("tracks monthly analytics for members", () => {
      const currentMonth = Math.floor(simnet.blockHeight / 4320);
      
      const monthlyAnalytics = simnet.callReadOnlyFn(
        contractName,
        "get-member-monthly-analytics",
        [wallet1, Cl.uint(currentMonth)],
        deployer
      );
      
      expect(monthlyAnalytics.result).toBeOk(
        expect.objectContaining({
          "deposits-made": "u1",
          "total-deposited": "u1000000",
          "withdrawals-made": "u0",
        })
      );
    });
  });

  describe("Analytics Integration with Existing Features", () => {
    it("updates analytics when processing withdrawals", () => {
      // Setup: Join pool and wait for lock period
      simnet.callPublicFn(contractName, "join-pool", [Cl.uint(2000000)], wallet1);
      
      // Advance blocks to pass lock period
      simnet.mineEmptyBlocks(200);
      
      // Request and process withdrawal
      simnet.callPublicFn(contractName, "request-withdrawal", [], wallet1);
      simnet.callPublicFn(contractName, "process-withdrawal", [], wallet1);
      
      const growthSummary = simnet.callReadOnlyFn(
        contractName,
        "get-pool-growth-summary",
        [],
        deployer
      );
      
      expect(growthSummary.result).toBeOk(
        expect.objectContaining({
          "total-transactions": "u3", // join, request, process
          "total-deposits": "u0", // Withdrawn
        })
      );
    });

    it("maintains analytics accuracy with multiple operations", () => {
      // Complex scenario with multiple members and operations
      simnet.callPublicFn(contractName, "join-pool", [Cl.uint(3000000)], wallet1);
      simnet.callPublicFn(contractName, "join-pool", [Cl.uint(7000000)], wallet2);
      
      simnet.callPublicFn(contractName, "deposit", [Cl.uint(2000000)], wallet1);
      simnet.callPublicFn(contractName, "deposit", [Cl.uint(1000000)], wallet2);
      
      const finalSummary = simnet.callReadOnlyFn(
        contractName,
        "get-pool-growth-summary",
        [],
        deployer
      );
      
      expect(finalSummary.result).toBeOk(
        expect.objectContaining({
          "total-members": "u2",
          "total-deposits": "u13000000", // 3M+7M+2M+1M
          "total-transactions": "u4", // 2 joins + 2 deposits
          "average-deposit-per-member": "u6500000", // 13M / 2
        })
      );
    });
  });
});
