// Package app holds the dependencies shared by every module. It imports
// nothing from other internal modules, so there are no import cycles.
package app

import (
	"database/sql"

	"stonerspots/backend/internal/config"
)

type Deps struct {
	DB  *sql.DB
	Cfg config.Config
}
