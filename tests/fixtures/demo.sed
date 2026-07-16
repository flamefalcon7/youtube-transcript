# Runner self-test fixture — NOT a learned rule. Demonstrates the format and proves
# run_tests.sh works on a fresh clone (your real rules + tests are gitignored, local).
# Illustrative example: Whisper commonly renders "Kubernetes" as "Kubernets"/"communities"
# in tech speech; a domain-scoped rule for the unambiguous misspelling looks like this:
s/[[:<:]]Kubernets[[:>:]]/Kubernetes/g
