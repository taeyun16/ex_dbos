import { DBOS } from "@dbos-inc/dbos-sdk";

const systemDatabaseUrl = process.env.DBOS_SYSTEM_DATABASE_URL;

if (!systemDatabaseUrl) {
  throw new Error("DBOS_SYSTEM_DATABASE_URL is required");
}

async function stepOne() {
  DBOS.logger.info("sample step completed");
  return "ok";
}

async function workflowFunction() {
  await DBOS.runStep(() => stepOne(), { name: "stepOne" });
  return { ok: true };
}

const sampleWorkflow = DBOS.registerWorkflow(workflowFunction);

async function main() {
  DBOS.setConfig({
    name: "ex-dbos-compose-worker",
    systemDatabaseUrl
  });

  await DBOS.launch();
  DBOS.logger.info("DBOS launched");

  if (process.env.DBOS_RUN_SAMPLE_WORKFLOW === "1") {
    const result = await sampleWorkflow();
    DBOS.logger.info(`sample workflow result: ${JSON.stringify(result)}`);
  }

  await new Promise(() => {});
}

main().catch((error) => {
  console.error("dbos worker failed:", error);
  process.exit(1);
});
