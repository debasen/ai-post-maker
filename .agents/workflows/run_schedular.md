---
description: Automatically creates and executes a multi-task automation schedule for Grok video generation with defined intervals.
---

# Run Schedular Workflow

This workflow automatically creates an execution schedule for the Grok automation workflow and runs it continuously. 

## Parameters
- `--project-<1|2>`: The project to run the automation for (e.g. `--project-1`).
- `--tasks-<N>`: The total number of tasks in the schedule. Half of these will be generation tasks, and half will be wait tasks (e.g. `--tasks-40` means 20 runs and 20 sleeps).

## Steps
1. **Create Artifact**: Generate an Antigravity task list artifact based on the parameters provided. The artifact should alternate between running the `/grok_automation_v4` workflow and waiting for a specified interval (default `sleep 600`).
2. **Execute**: Begin executing the generated tasks sequentially.
3. **Run Automation**: For generation tasks, trigger the `/grok_automation_v4` workflow for the specified project to process 1 item.
4. **Wait**: For wait tasks, run the `sleep 600` command and wait for its completion.
5. **Update**: Update the task list artifact's checkboxes as each task completes.
6. **Continuous**: Continue executing all tasks until the entire list is completed. Do not stop until all `<N>` tasks are finished.
