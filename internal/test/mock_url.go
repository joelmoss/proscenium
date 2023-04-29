package test

import "github.com/h2non/gock"

func MockURL(urlPath string, response string) {
	gock.New("https://proscenium.test").Get(urlPath).Reply(200).BodyString(response)
}
