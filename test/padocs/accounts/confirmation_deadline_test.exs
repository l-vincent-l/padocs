defmodule Padocs.Accounts.ConfirmationDeadlineTest do
  use Padocs.DataCase, async: true

  alias Padocs.{Accounts, Fixtures}

  test "an unconfirmed account has 7 days from its registration" do
    user = Fixtures.register_user()
    deadline = Accounts.confirmation_deadline(user)

    assert DateTime.diff(deadline, user.inserted_at, :day) == 7
    refute Accounts.confirmation_expired?(user)
    refute Accounts.confirmation_expired?(user, DateTime.add(deadline, -1))
    assert Accounts.confirmation_expired?(user, deadline)
  end

  test "a confirmed account has no deadline" do
    user = Fixtures.confirmed_user()

    assert Accounts.confirmation_deadline(user) == nil
    refute Accounts.confirmation_expired?(user, DateTime.add(DateTime.utc_now(), 30, :day))
  end
end
