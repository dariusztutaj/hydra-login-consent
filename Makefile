APP_NAME=service-catalog-tester
APP_IMG=$(DOCKER_PUSH_REPOSITORY)$(DOCKER_PUSH_DIRECTORY)/$(APP_NAME)
TAG=$(DOCKER_TAG)
BINARY=$(APP_NAME)

.PHONY: build
build:
	./before-commit.sh ci

.PHONY: build-image
build-image:
	docker build -t $(APP_NAME):latest .

.PHONY: push-image
push-image:
	docker tag $(APP_NAME) $(TESTER_IMG):$(TAG)
	docker push $(APP_IMG):$(TAG)

.PHONY: ci-pr
ci-pr: build build-image push-image

.PHONY: ci-main
ci-main: build build-image push-image

.PHONY: ci-release
ci-release: build build-image push-image

.PHONY: clean
clean:
	rm -f $(BINARY)