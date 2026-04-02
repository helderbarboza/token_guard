# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     TokenGuard.Repo.insert!(%TokenGuard.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias TokenGuard.Repo
alias TokenGuard.Tokens

IO.puts("Creating 100 tokens...")

Tokens.create_tokens(100)

IO.puts("Done! Created 100 tokens.")
