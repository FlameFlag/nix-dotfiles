package runner

import (
	"fmt"
	"io"
	"time"
)

func logf(writer io.Writer, format string, args ...any) {
	fmt.Fprintf(writer, "%s %s\n", time.Now().Format("2006-01-02T15:04:05-07:00"), fmt.Sprintf(format, args...))
}
