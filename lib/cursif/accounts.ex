defmodule Cursif.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Cursif.Repo

  alias Cursif.Accounts.{User, UserNotifier}
  alias Argon2

  @doc """
  Returns the list of accounts.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  @spec list_users :: list(User.t())
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(binary()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_user(map()) :: {:ok, User.t()} | {:error, %Ecto.Changeset{}}
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, %Ecto.Changeset{}}
  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, %Ecto.Changeset{}}
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user(User.t(), map()) ::  %Ecto.Changeset{data: User.t()}
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Authenticates a user by its username and password

  ## Examples

      iex> authenticate_user("ghopper@example.com", "GraceHopper1234")
      {:ok, %User{}}

      iex> authenticate_user("ghopper@example.com", "BadPassword")
      {:error, :invalid_credentials}
  """
  @spec authenticate_user(String.t(), String.t()) :: {:ok, User.t(), String.t()} | {:error, :invalid_credentials}
  def authenticate_user(email, plain_text_password) do
    if Repo.get_by(User, confirmed_at: nil) do
      {:error, :not_confirmed}
    else
      case Repo.get_by(User, email: email) do
        nil ->
          Argon2.no_user_verify()
          {:error, :invalid_credentials}
        user ->
          if Argon2.verify_pass(plain_text_password, user.hashed_password) do
            {:ok, user, create_token(user)}
          else
            {:error, :invalid_credentials}
          end
      end
    end
  end

  @spec create_token(User.t()) :: {:ok, String.t(), map()} | {:error, String.t()}
  def create_token(user, stategy \\ :guardian)

  def create_token(user, :guardian) do
    case Cursif.Guardian.encode_and_sign(user, %{}) do
      {:ok, token, _full_claims} -> token
    end
  end

  def create_token(user, :phoenix_token) do
    {:ok, Phoenix.Token.sign(CursifWeb.Endpoint, "user id", user.id)}
  end

  def generate_validation_token(user) do
    token = Phoenix.Token.sign(CursifWeb.Endpoint, "user confirm", user.id)
    user = User.put_confirmation_token(user, %{confirmation_token: token}) |> Repo.update()

    {:ok, user}
  end

  @doc """
  Generates a confirmation token.

  ## Examples

      iex> generate_confirmation_token(user)
      {:ok, %User{}}

      iex> generate_confirmation_token(user)
      {:error, :already_confirmed}
  """
  def deliver_user_confirmation_instructions(%User{} = user) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {:ok, user} = generate_validation_token(user)
      
      url = build_url_to_deliver(user.confirmation_token)
      UserNotifier.deliver_confirmation_instructions(user, url)
    end
  end

  def build_url_to_deliver(token) do
    # need to update this for production env to use the correct base_url
    base_url = "http://0.0.0.0:4000/users/confirm"
    query_params = "?token=" <> token
    "#{base_url}#{query_params}"
  end

  @doc """
  Confirms a user by its confirmation token

  ## Examples

      iex> confirm_user("token")
      {:ok, %User{}}

      iex> confirm_user("bad_token")
      {:error, :invalid_token}
  """
  @spec get_user_by_confirmation_token(String.t()) :: {:ok, User.t()} | {:error, atom()}
  def get_user_by_confirmation_token(token) do
    case Repo.get_by(User, confirmation_token: token) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end
end
