### Deploys (agent-deploy)

- Deploy target and adapter: `.claude/OPERATIONS.md` § Deploys. Only the user starts
  `/agent-deploy:verify-deploy` and `/agent-deploy:promote-deploy`. A deploy counts once a deployment
  created after the merge has finished; an accepted webhook or a green CI run is not that proof.
- `scripts/deploy/*.sh` use the network, so Claude asks first. The user runs `trigger-deploy.sh`,
  whose webhook URL is a secret, in their own terminal.
