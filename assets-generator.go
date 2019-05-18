// +build ignore

package main

import (
	"log"
	"io/ioutil"
	"regexp"
	"net/http"

	"github.com/shurcooL/vfsgen"
)

func main() {
	genFile := "cmd/serve/assets-prod.go"

	// Generate the embedded, virtual file system from the contents of "view/"
	err := vfsgen.Generate(http.Dir("view"), vfsgen.Options{
		Filename:     genFile,
		PackageName:  "serve",
		BuildTags:    "!dev",
		VariableName: "assets",
	})

	if err != nil {
		log.Fatalln(err)
	} else {
		dummyTimes(genFile)
	}
}

// dummyTimes replaces all modification times
// of a vfsgen generated virtual file system with a dummy time.
// We may want to do this to prevent constant changes in those values,
// which we are not interested in anyway.
func dummyTimes(file string) {
	// Read the generated file contents
	contentBytes, err := ioutil.ReadFile(file)
	if err != nil {
		panic(err)
	}
	var content = string(contentBytes)

	// Set fixed modTime
	var re = regexp.MustCompilePOSIX(`modTime[:]([[:space:]]*)time[.]Date.*$`)
	newContent := re.ReplaceAllString(content, `modTime:${1}time.Date(2019, 1, 1, 1, 1, 1, 1, time.UTC),`)

	// Write back to the generated file
	err2 := ioutil.WriteFile(file, []byte(newContent), 0644)
	if err2 != nil {
		panic(err2)
	}
}

