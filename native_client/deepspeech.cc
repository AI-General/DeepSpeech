#include "deepspeech.h"
#include "deepspeech_utils.h"
#include "alphabet.h"
#include "beam_search.h"

#include "tensorflow/core/public/session.h"
#include "tensorflow/core/platform/env.h"

using namespace tensorflow;
using tensorflow::ctc::CTCBeamSearchDecoder;
using tensorflow::ctc::CTCDecoder;

namespace DeepSpeech {

class Private {
  public:
    Session* session;
    GraphDef graph_def;
    int ncep;
    int ncontext;
    Alphabet* alphabet;
    KenLMBeamScorer* scorer;
    int beam_width;
};

Model::Model(const char* aModelPath, int aNCep, int aNContext,
             const char* aAlphabetConfigPath, const char* aLMPath,
             const char* aTriePath, int aBeamWidth, float aLMWeight,
             float aWordCountWeight, float aValidWordCountWeight)
{
  mPriv = new Private;
  mPriv->ncep = aNCep;
  mPriv->ncontext = aNContext;
  mPriv->session = NULL;
  mPriv->alphabet = new Alphabet(aAlphabetConfigPath);

  if (!aModelPath) {
    return;
  }

  Status status = NewSession(SessionOptions(), &mPriv->session);
  if (!status.ok()) {
    return;
  }

  status = ReadBinaryProto(Env::Default(), aModelPath, &mPriv->graph_def);
  if (!status.ok()) {
    mPriv->session->Close();
    mPriv->session = NULL;
    return;
  }

  status = mPriv->session->Create(mPriv->graph_def);
  if (!status.ok()) {
    mPriv->session->Close();
    mPriv->session = NULL;
    return;
  }

  mPriv->ncep = aNCep;
  mPriv->ncontext = aNContext;

  mPriv->alphabet = new Alphabet(aAlphabetConfigPath);

  mPriv->scorer = new KenLMBeamScorer(aLMPath, aTriePath, aAlphabetConfigPath,
                                      aLMWeight, aWordCountWeight, aValidWordCountWeight);

  mPriv->beam_width = aBeamWidth;
}

Model::~Model()
{
  if (mPriv->session) {
    mPriv->session->Close();
  }

  delete mPriv->alphabet;
  delete mPriv->scorer;

  delete mPriv;
}

void
Model::getInputVector(const short* aBuffer, unsigned int aBufferSize,
                           int aSampleRate, float** aMfcc, int* aNFrames,
                           int* aFrameLen)
{
  return audioToInputVector(aBuffer, aBufferSize, aSampleRate, mPriv->ncep,
                            mPriv->ncontext, aMfcc, aNFrames, aFrameLen);
}

char*
Model::infer(float* aMfcc, int aNFrames, int aFrameLen)
{
  const int batch_size = 1;
  const int top_paths = 1;
  const int timesteps = aNFrames;
  const size_t num_classes = mPriv->alphabet->GetSize() + 1; // +1 for blank

  float input_data_mat[timesteps][batch_size][num_classes];

  const int frameSize = mPriv->ncep + (2 * mPriv->ncep * mPriv->ncontext);
  if (aFrameLen == 0) {
    aFrameLen = frameSize;
  } else if (aFrameLen < frameSize) {
    std::cerr << "mfcc features array is too small (expected " <<
      frameSize << ", got " << aFrameLen << ")\n";
    return NULL;
  }

  Tensor input(DT_FLOAT, TensorShape({1, aNFrames, frameSize}));

  auto input_mapped = input.tensor<float, 3>();
  for (int i = 0, idx = 0; i < aNFrames; i++) {
    for (int j = 0; j < frameSize; j++, idx++) {
      input_mapped(0, i, j) = aMfcc[idx];
    }
    idx += (aFrameLen - frameSize);
  }

  Tensor n_frames(DT_INT32, TensorShape({1}));
  n_frames.scalar<int>()() = aNFrames;

  std::vector<Tensor> outputs;
  Status status = mPriv->session->Run(
    {{ "input_node", input }, { "input_lengths", n_frames }},
    {"Reshape_3"}, {}, &outputs);
  if (!status.ok()) {
    std::cerr << "Error running session: " << status.ToString() << "\n";
    return NULL;
  }

  auto outputs_mapped = outputs[0].tensor<float, 3>();
  // The CTCDecoder works with log-probs.
  for (int t = 0; t < timesteps; ++t) {
    for (int b = 0; b < batch_size; ++b) {
      for (int c = 0; c < num_classes; ++c) {
        input_data_mat[t][b][c] = outputs_mapped(t, b, c);
      }
    }
  }

  CTCBeamSearchDecoder<KenLMBeamState> decoder(num_classes,
                              /* beam width */ mPriv->beam_width,
                                               mPriv->scorer,
                              /* batch size */ 1);

  // Raw data containers (arrays of floats, ints, etc.).
  int sequence_lengths[batch_size] = {timesteps};

  // Convert data containers to the format accepted by the decoder, simply
  // mapping the memory from the container to an Eigen::ArrayXi,::MatrixXf,
  // using Eigen::Map.
  Eigen::Map<const Eigen::ArrayXi> seq_len(&sequence_lengths[0], batch_size);
  std::vector<Eigen::Map<const Eigen::MatrixXf>> inputs;
  inputs.reserve(timesteps);
  for (int t = 0; t < timesteps; ++t) {
    inputs.emplace_back(&input_data_mat[t][0][0], batch_size, num_classes);
  }

  // Prepare containers for output and scores.
  // CTCDecoder::Output is std::vector<std::vector<int>>
  std::vector<CTCDecoder::Output> decoder_outputs(top_paths);
  for (CTCDecoder::Output& output : decoder_outputs) {
    output.resize(batch_size);
  }
  float score[batch_size][top_paths] = {{0.0}};
  Eigen::Map<Eigen::MatrixXf> scores(&score[0][0], batch_size, top_paths);

  decoder.Decode(seq_len, inputs, &decoder_outputs, &scores).ok();

  // Output is an array of shape (1, n_results, result_length).
  // In this case, n_results is also equal to 1.
  size_t output_length = decoder_outputs[0][0].size() + 1;

  size_t decoded_length = 1; // add 1 for the \0
  for (int i = 0; i < output_length - 1; i++) {
    int64 character = decoder_outputs[0][0][i];
    const std::string& str = mPriv->alphabet->StringFromLabel(character);
    decoded_length += str.size();
  }

  char* output = (char*)malloc(sizeof(char) * decoded_length);
  char* pen = output;
  for (int i = 0; i < output_length - 1; i++) {
    int64 character = decoder_outputs[0][0][i];
    const std::string& str = mPriv->alphabet->StringFromLabel(character);
    strncpy(pen, str.c_str(), str.size());
    pen += str.size();
  }
  *pen = '\0';

  return output;
}

char*
Model::stt(const short* aBuffer, unsigned int aBufferSize, int aSampleRate)
{
  float* mfcc;
  char* string;
  int n_frames;

  getInputVector(aBuffer, aBufferSize, aSampleRate, &mfcc, &n_frames, NULL);
  string = infer(mfcc, n_frames);
  free(mfcc);
  return string;
}

}
