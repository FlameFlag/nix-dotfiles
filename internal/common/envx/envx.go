package envx

import env "github.com/caarlos0/env/v11"

func Parse[T any]() (T, error) {
	return env.ParseAs[T]()
}

func MustParse[T any]() T {
	config, err := Parse[T]()
	if err != nil {
		panic(err)
	}
	return config
}
