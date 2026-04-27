---
description: Automatically executes a recurring schedule for following suggested accounts on Instagram with randomized wait intervals.
---

# Instagram Schedular Workflow

This workflow automatically creates or resumes an execution schedule for the Instagram follow suggestions workflow and runs it continuously with randomized delays.

## Parameters
None required.

## Steps
1. **Check for Existing Schedule**: Look in the artifacts directory for an existing task list named `instagram_automation_task_list.md`.
2. **Create or Resume**:
   - If an existing task list is found, identify the first unchecked task and **resume** from there.
   - If no existing task list is found, **create** a new Antigravity task list artifact. The artifact should alternate between running the `/instagram_follow_suggestions` workflow and waiting for a randomized interval.
3. **Random Wait Interval**: (If creating a new schedule) For each wait task, calculate a random sleep duration between 10 minutes (600s) and 45 minutes (2700s).
4. **Execute**: Begin executing the generated tasks sequentially (starting from the first incomplete task).
5. **Run Automation**: For follow tasks, trigger the `/instagram_follow_suggestions` workflow.
6. **Wait**: For wait tasks, run the `sleep <random_duration>` command in the background and use `command_status` to wait for its completion.
7. **Update**: Update the task list artifact's checkboxes as each task completes.
8. **Continuous**: Continue executing all tasks until the entire list is completed.
