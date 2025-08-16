from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    pg_dsn: str

    class Config:
        env_file = ".env"


settings = Settings()
