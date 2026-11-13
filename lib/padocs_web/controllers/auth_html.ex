defmodule PadocsWeb.AuthHTML do
  @moduledoc "The pages of AuthController."
  use PadocsWeb, :html

  def sign_in(assigns) do
    ~H"""
    <.auth_page flash={@flash} title="Sign in">
      <.form for={@form} id="password-sign-in" action={~p"/sign-in"} class="flex flex-col gap-1">
        <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
        />
        <.input field={@form[:remember_me]} type="checkbox" label="Remember me" value="true" />
        <.button variant="primary" class="btn btn-primary w-full">Sign in</.button>
      </.form>
      <p class="text-sm">
        <.link href={~p"/reset"} class="link">Forgot your password?</.link>
        · <.link href={~p"/register"} class="link">Need an account?</.link>
      </p>

      <div class="divider">or</div>

      <.form for={@form} id="magic-link" action={~p"/magic-link"} class="flex flex-col gap-1">
        <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
        <.button class="btn w-full">Email me a sign-in link</.button>
      </.form>

      <div class="divider">or</div>

      <a href="/auth/user/github" class="btn w-full">
        <.icon name="hero-code-bracket" class="size-5" /> Sign in with GitHub
      </a>
      <a href="/auth/user/gitlab" class="btn w-full">
        <img src={~p"/images/gitlab.svg"} alt="" class="size-5" /> Sign in with GitLab
      </a>
    </.auth_page>
    """
  end

  def register(assigns) do
    ~H"""
    <.auth_page flash={@flash} title="Register">
      <.form for={@form} id="register" action={~p"/register"} class="flex flex-col gap-1">
        <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="new-password"
          required
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Password confirmation"
          autocomplete="new-password"
          required
        />
        <.button variant="primary" class="btn btn-primary w-full">Register</.button>
      </.form>
      <p class="text-sm">
        <.link href={~p"/sign-in"} class="link">Already have an account?</.link>
      </p>
    </.auth_page>
    """
  end

  def reset(assigns) do
    ~H"""
    <.auth_page flash={@flash} title="Reset your password">
      <.form for={@form} id="reset" action={~p"/reset"} class="flex flex-col gap-1">
        <.input field={@form[:email]} type="email" label="Email" autocomplete="username" required />
        <.button variant="primary" class="btn btn-primary w-full">Send a reset link</.button>
      </.form>
    </.auth_page>
    """
  end

  def edit_password(assigns) do
    ~H"""
    <.auth_page flash={@flash} title="Choose a new password">
      <.form
        for={@form}
        id="edit-password"
        action={~p"/password-reset/#{@token}"}
        class="flex flex-col gap-1"
      >
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="new-password"
          required
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Password confirmation"
          autocomplete="new-password"
          required
        />
        <.button variant="primary" class="btn btn-primary w-full">Reset the password</.button>
      </.form>
    </.auth_page>
    """
  end

  def email_link(assigns) do
    ~H"""
    <.auth_page flash={@flash} title={@title}>
      <p class="text-sm">{@email}</p>
      <.form for={%{}} id="link" action={@action} class="flex flex-col gap-1">
        <.input name="remember_me" type="checkbox" label="Remember me" value="true" />
        <.button variant="primary" class="btn btn-primary w-full">{@title}</.button>
      </.form>
    </.auth_page>
    """
  end

  attr :flash, :map, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp auth_page(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex w-full max-w-sm flex-col gap-4">
        <h1 class="text-xl uppercase">{@title}</h1>
        {render_slot(@inner_block)}
      </div>
    </Layouts.app>
    """
  end
end
