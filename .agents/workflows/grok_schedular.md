---
description: Automatically creates and executes a multi-task automation schedule for Grok video generation with defined intervals.
---

# Grok Schedular Workflow

This workflow automatically creates or resumes an execution schedule for the Grok automation workflow and runs it continuously.

## Parameters
- `--project-<1|2>`: The project to run the automation for (e.g. `--project-1`).
- `--tasks-<N>`: The total number of tasks in the schedule. Half of these will be generation tasks, and half will be wait tasks (e.g. `--tasks-40` means 20 runs and 20 sleeps).

## Steps
1. **Check for Existing Schedule**: Look in the artifacts directory for an existing task list named `project_<N>_automation_task_list.md`.
2. **Create or Resume**:
   - If an existing task list is found, identify the first unchecked task and **resume** from there.
   - If no existing task list is found, **create** a new Antigravity task list artifact based on the parameters provided. The artifact should alternate between running the `/grok_automation_v4` workflow and waiting for a specified interval (default `sleep 600`).
3. **Execute**: Begin executing the tasks sequentially (starting from the first incomplete task).
4. **Run Automation**: For generation tasks, trigger the `/grok_automation_v4` workflow for the specified project to process 1 item.
5. **Wait**: For wait tasks, run the `sleep 600` command in the background and use `command_status` to wait for its completion.
6. **Update**: Update the task list artifact's checkboxes as each task completes.
7. **Continuous**: Continue executing all tasks until the entire list is completed. Do not stop until all tasks in the list are finished.
