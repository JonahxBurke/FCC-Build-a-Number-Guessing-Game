#!/bin/bash

set -u

db_name="number_guess"
psql_game() {
  psql -X -q -t -A -F ' ' -v ON_ERROR_STOP=1 -U freecodecamp -d "$db_name" "$@"
}

printf 'Enter your username: '
IFS= read -r username || exit 0

if [[ -z $username || ${#username} -gt 22 ]]; then
  printf 'Username must contain between 1 and 22 characters.\n' >&2
  exit 1
fi

user_id=$(psql_game -v player="$username" <<'SQL'
INSERT INTO users (username)
VALUES (:'player')
ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
RETURNING user_id;
SQL
) || exit 1

stats=$(psql_game -v id="$user_id" <<'SQL'
SELECT COUNT(g.game_id), COALESCE(MIN(g.guesses), 0)
FROM games g
WHERE g.user_id = :'id';
SQL
) || exit 1
read -r games_played best_guesses <<< "$stats"

if (( games_played == 0 )); then
  printf 'Welcome, %s! It looks like this is your first time here.\n' "$username"
else
  printf 'Welcome back, %s! You have played %s games, and your best game took %s guesses.\n' \
    "$username" "$games_played" "$best_guesses"
fi

secret_number=$(( RANDOM % 1000 + 1 ))
guess_count=0
solved=0
printf 'Guess the secret number between 1 and 1000: '

while IFS= read -r guess; do
  if [[ ! $guess =~ ^-?[0-9]+$ ]]; then
    printf 'That is not an integer, guess again: '
    continue
  fi

  guess_count=$((guess_count + 1))
  if [[ $guess == -* ]]; then
    printf "It's higher than that, guess again: "
    continue
  fi

  # Strip leading zeroes before arithmetic so inputs such as 0007 work in base 10.
  normalized_guess=${guess#"${guess%%[!0]*}"}
  [[ -n $normalized_guess ]] || normalized_guess=0

  # Values longer than four digits cannot equal the secret and are always too high.
  if (( ${#normalized_guess} > 4 )); then
    printf "It's lower than that, guess again: "
    continue
  fi

  numeric_guess=$((10#$normalized_guess))

  if (( numeric_guess < secret_number )); then
    printf "It's higher than that, guess again: "
  elif (( numeric_guess > secret_number )); then
    printf "It's lower than that, guess again: "
  else
    solved=1
    break
  fi
done

if (( solved == 0 )); then
  exit 0
fi

printf 'You guessed it in %s tries. The secret number was %s. Nice job!\n' \
  "$guess_count" "$secret_number"
psql_game -v id="$user_id" -v tries="$guess_count" <<'SQL' >/dev/null
INSERT INTO games (user_id, guesses)
VALUES (:'id', :'tries');
SQL
